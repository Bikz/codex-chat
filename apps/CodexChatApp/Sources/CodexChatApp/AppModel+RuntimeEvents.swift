import CodexChatCore
import CodexExtensions
import CodexKit
import Foundation

extension AppModel {
    func handleRuntimeEventBatch(_ events: [CodexRuntimeEvent]) {
        guard !events.isEmpty else {
            return
        }

        for event in events {
            handleRuntimeEvent(event)
        }
    }

    func handleRuntimeEvent(_ event: CodexRuntimeEvent) {
        let clock = ContinuousClock()
        let startedAt = clock.now
        defer {
            let duration = clock.now - startedAt
            let components = duration.components
            let durationMS = (Double(components.seconds) + (Double(components.attoseconds) / 1_000_000_000_000_000_000)) * 1000
            Task {
                await PerformanceTracer.shared.record(
                    name: "runtime.event.\(event.performanceName)",
                    durationMS: durationMS
                )
            }
        }

        switch event {
        case let .threadStarted(threadID):
            appendLog(.debug, "Runtime thread started: \(threadID)")
            if let localThreadID = resolveLocalThreadID(runtimeThreadID: threadID, itemID: nil),
               let context = activeTurnContext(for: localThreadID)
            {
                emitExtensionEvent(
                    .threadStarted,
                    projectID: context.projectID,
                    projectPath: context.projectPath,
                    threadID: context.localThreadID,
                    turnID: context.localTurnID.uuidString,
                    payload: ["runtimeThreadID": threadID]
                )
            }

        case let .turnStarted(runtimeThreadID, turnID):
            guard let localThreadID = resolveLocalThreadID(
                runtimeThreadID: runtimeThreadID,
                itemID: nil,
                runtimeTurnID: turnID
            ),
                let context = updateActiveTurnContext(for: localThreadID, mutate: { updated in
                    updated.runtimeTurnID = turnID
                })
            else {
                appendLog(.debug, "Turn started without thread mapping: \(turnID)")
                return
            }

            appendEntry(
                .actionCard(
                    ActionCard(
                        threadID: context.localThreadID,
                        method: "turn/started",
                        title: "Turn started",
                        detail: "turnId=\(turnID)"
                    )
                ),
                to: context.localThreadID
            )
            emitExtensionEvent(
                .turnStarted,
                projectID: context.projectID,
                projectPath: context.projectPath,
                threadID: context.localThreadID,
                turnID: turnID
            )
            markThreadUnreadIfNeeded(context.localThreadID)

        case let .assistantMessageDelta(runtimeThreadID, runtimeTurnID, itemID, delta):
            guard let localThreadID = resolveLocalThreadID(
                runtimeThreadID: runtimeThreadID,
                itemID: itemID,
                runtimeTurnID: runtimeTurnID
            ) else {
                appendLog(.debug, "Dropped delta with no thread mapping")
                return
            }

            enqueueAssistantDeltaForUI(delta, itemID: itemID, threadID: localThreadID)
            if let context = activeTurnContext(for: localThreadID) {
                emitExtensionEvent(
                    .assistantDelta,
                    projectID: context.projectID,
                    projectPath: context.projectPath,
                    threadID: context.localThreadID,
                    turnID: context.localTurnID.uuidString,
                    payload: ["itemID": itemID, "delta": delta]
                )
            }
            markThreadUnreadIfNeeded(localThreadID)

        case let .commandOutputDelta(output):
            handleCommandOutputDelta(output)

        case let .followUpSuggestions(batch):
            handleFollowUpSuggestions(batch)

        case let .fileChangesUpdated(update):
            handleFileChangesUpdate(update)

        case let .approvalRequested(request):
            handleApprovalRequest(request)

        case let .action(action):
            handleRuntimeAction(action)

        case let .turnCompleted(completion):
            conversationUpdateScheduler.flushImmediately()
            let localThreadID = resolveLocalThreadID(
                runtimeThreadID: completion.threadID,
                itemID: nil,
                runtimeTurnID: completion.turnID
            )

            if let localThreadID,
               let context = removeActiveTurnContext(for: localThreadID)
            {
                let detail = if let errorMessage = completion.errorMessage {
                    "status=\(completion.status), error=\(errorMessage)"
                } else {
                    "status=\(completion.status)"
                }

                appendEntry(
                    .actionCard(
                        ActionCard(
                            threadID: context.localThreadID,
                            method: "turn/completed",
                            title: "Turn completed",
                            detail: detail
                        )
                    ),
                    to: context.localThreadID
                )

                processModChangesIfNeeded(context: context)
                let eventName: ExtensionEventName = isFailureCompletion(completion) ? .turnFailed : .turnCompleted
                var payload = ["status": completion.status]
                if let errorMessage = completion.errorMessage {
                    payload["error"] = errorMessage
                }
                emitExtensionEvent(
                    eventName,
                    projectID: context.projectID,
                    projectPath: context.projectPath,
                    threadID: context.localThreadID,
                    turnID: completion.turnID ?? context.localTurnID.uuidString,
                    turnStatus: completion.status,
                    payload: payload
                )
                markThreadUnreadIfNeeded(context.localThreadID)

                Task {
                    await turnConcurrencyScheduler.release(threadID: context.localThreadID)
                    await turnPersistenceScheduler.enqueue(context: context, completion: completion)
                }
            } else {
                appendLog(.debug, "Turn completed without active context: \(completion.status)")
                if let localThreadID {
                    Task {
                        await turnConcurrencyScheduler.release(threadID: localThreadID)
                    }
                }
            }
            requestAutoDrain(reason: "turn completed")

        case let .accountUpdated(authMode):
            appendLog(.info, "Account mode updated: \(authMode.rawValue)")
            Task {
                try? await refreshAccountState()
                await refreshRuntimeModelCatalog()
                requestAutoDrain(reason: "account updated")
            }

        case let .accountLoginCompleted(completion):
            stopChatGPTLoginPolling()
            if completion.success {
                accountStatusMessage = "Login completed."
                appendLog(.info, "Login completed")
                requestAutoDrain(reason: "account login completed")
            } else {
                let detail = completion.error ?? "Unknown error"
                accountStatusMessage = "Login failed: \(detail)"
                appendLog(.error, "Login failed: \(detail)")
            }
            Task {
                try? await refreshAccountState()
                await refreshRuntimeModelCatalog()
            }
        }
    }

    private func handleRuntimeAction(_ action: RuntimeAction) {
        let classification = TranscriptActionPolicy.classify(
            method: action.method,
            title: action.title,
            detail: action.detail,
            itemType: action.itemType
        )
        let transcriptDetail = action.method == "runtime/stderr"
            ? sanitizeLogText(action.detail)
            : action.detail

        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: action.threadID,
            itemID: action.itemID,
            runtimeTurnID: action.turnID
        )

        if let localThreadID,
           let runtimeThreadID = action.threadID,
           dequeuePendingRuntimeRepairSuggestion(for: runtimeThreadID)
        {
            appendRuntimeRepairSuggestionIfNeeded(to: localThreadID)
        }

        if action.method == "runtime/stderr" {
            let isRolloutPathWarning = TranscriptActionPolicy.isRolloutPathStateDBWarning(action.detail)
            let level: LogLevel = TranscriptActionPolicy.isCriticalStderr(action.detail) ? .error : .warning

            if let localThreadID {
                appendThreadLog(level: level, text: action.detail, to: localThreadID)
                if isRolloutPathWarning {
                    appendRuntimeRepairSuggestionIfNeeded(to: localThreadID)
                }
            } else if isRolloutPathWarning, let runtimeThreadID = action.threadID {
                enqueuePendingRuntimeRepairSuggestion(for: runtimeThreadID)
            }
            appendLog(
                level,
                action.detail
            )
        }

        if action.method == "turn/start/error" || action.method == "turn/error" {
            conversationUpdateScheduler.flushImmediately()
        }

        if action.method == "runtime/terminated" {
            conversationUpdateScheduler.flushImmediately()
            handleRuntimeTermination(detail: action.detail)
        }

        guard let localThreadID else {
            appendLog(.debug, "Runtime action without thread mapping: \(action.method)")
            return
        }

        if action.itemType == "commandExecution",
           let itemID = action.itemID
        {
            localThreadIDByCommandItemID[itemID] = localThreadID
        }

        let card = ActionCard(
            threadID: localThreadID,
            method: action.method,
            title: action.title,
            detail: transcriptDetail
        )

        captureWorkerTraceIfPresent(
            runtimeAction: action,
            threadID: localThreadID,
            transcriptDetail: transcriptDetail
        )

        appendEntry(.actionCard(card), to: localThreadID)
        markThreadUnreadIfNeeded(localThreadID)
        if let context = extensionProjectContext(forThreadID: localThreadID) {
            emitExtensionEvent(
                .actionCard,
                projectID: context.projectID,
                projectPath: context.projectPath,
                threadID: localThreadID,
                turnID: action.turnID,
                payload: [
                    "method": action.method,
                    "title": action.title,
                    "detail": action.detail,
                ]
            )
        }

        _ = updateActiveTurnContext(for: localThreadID, mutate: { context in
            context.actions.append(card)
        })

        if classification == .lifecycleNoise {
            appendLog(.debug, "Lifecycle runtime action received: \(action.method)")
        }
    }

    private func enqueueAssistantDeltaForUI(_ delta: String, itemID: String, threadID: UUID) {
        conversationUpdateScheduler.enqueue(
            delta: delta,
            threadID: threadID,
            itemID: itemID
        )
    }

    func applyCoalescedAssistantDeltaBatch(_ batch: [ConversationUpdateScheduler.BatchItem]) {
        guard !batch.isEmpty else {
            return
        }

        for item in batch {
            appendAssistantDelta(item.delta, itemID: item.itemID, to: item.threadID)
            _ = updateActiveTurnContext(for: item.threadID, mutate: { context in
                context.assistantText += item.delta
            })
        }
    }

    private func handleCommandOutputDelta(_ output: RuntimeCommandOutputDelta) {
        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: output.threadID,
            itemID: output.itemID,
            runtimeTurnID: output.turnID
        )

        guard let localThreadID else {
            appendLog(.debug, "Command output delta without thread mapping")
            return
        }

        enqueueThreadLog(
            level: .info,
            text: output.delta,
            to: localThreadID
        )
    }

    private func handleFileChangesUpdate(_ update: RuntimeFileChangeUpdate) {
        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: update.threadID,
            itemID: update.itemID,
            runtimeTurnID: update.turnID
        )

        guard let localThreadID else {
            appendLog(.debug, "File changes update without thread mapping")
            return
        }

        reviewChangesByThreadID[localThreadID] = update.changes
    }

    private func handleApprovalRequest(_ request: RuntimeApprovalRequest) {
        approvalStatusMessage = nil

        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: request.threadID,
            itemID: request.itemID,
            runtimeTurnID: request.turnID
        )

        guard let localThreadID else {
            unscopedApprovalRequest = request
            syncApprovalPresentationState()
            appendLog(.warning, "Approval request arrived without local thread mapping")
            return
        }

        approvalStateMachine.enqueue(request, threadID: localThreadID)
        syncApprovalPresentationState()

        let summary = approvalSummary(for: request)
        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: localThreadID,
                    method: request.method,
                    title: "Approval requested",
                    detail: summary
                )
            ),
            to: localThreadID
        )
        markThreadUnreadIfNeeded(localThreadID)
        if let context = extensionProjectContext(forThreadID: localThreadID) {
            emitExtensionEvent(
                .approvalRequested,
                projectID: context.projectID,
                projectPath: context.projectPath,
                threadID: localThreadID,
                payload: [
                    "method": request.method,
                    "summary": summary,
                    "kind": request.kind.rawValue,
                ]
            )
        }
    }

    func resolveLocalThreadID(runtimeThreadID: String?, itemID: String?, runtimeTurnID: String? = nil) -> UUID? {
        if let itemID, let threadID = localThreadIDByCommandItemID[itemID] {
            return threadID
        }

        if let runtimeTurnID,
           let mapped = localThreadID(for: runtimeTurnID)
        {
            return mapped
        }

        if let runtimeThreadID {
            if let mapped = localThreadIDByRuntimeThreadID[runtimeThreadID] {
                return mapped
            }
            if let activeContext = activeTurnContextsByThreadID.values.first(where: { $0.runtimeThreadID == runtimeThreadID }) {
                return activeContext.localThreadID
            }
        }

        if activeTurnContextsByThreadID.count == 1 {
            return activeTurnContextsByThreadID.first?.key
        }

        return nil
    }

    private func isFailureCompletion(_ completion: RuntimeTurnCompletion) -> Bool {
        if completion.errorMessage != nil {
            return true
        }
        let normalized = completion.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("fail")
            || normalized.contains("error")
            || normalized.contains("cancel")
    }

    private func appendRuntimeRepairSuggestionIfNeeded(to threadID: UUID) {
        let insertion = runtimeRepairSuggestedThreadIDs.insert(threadID)
        guard insertion.inserted else {
            return
        }

        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: threadID,
                    method: "runtime/repair-suggested",
                    title: "Repair Codex Home",
                    detail: "Runtime reported missing rollout path metadata. Open Settings > Storage and run Repair Codex Home."
                )
            ),
            to: threadID
        )
        markThreadUnreadIfNeeded(threadID)
    }

    private func enqueuePendingRuntimeRepairSuggestion(for runtimeThreadID: String) {
        runtimeRepairPendingRuntimeThreadIDs.insert(runtimeThreadID)
    }

    private func dequeuePendingRuntimeRepairSuggestion(for runtimeThreadID: String) -> Bool {
        runtimeRepairPendingRuntimeThreadIDs.remove(runtimeThreadID) != nil
    }

    func clearPendingRuntimeRepairSuggestions() {
        runtimeRepairPendingRuntimeThreadIDs.removeAll()
    }
}

private extension CodexRuntimeEvent {
    var performanceName: String {
        switch self {
        case .threadStarted:
            "threadStarted"
        case .turnStarted:
            "turnStarted"
        case .assistantMessageDelta:
            "assistantDelta"
        case .commandOutputDelta:
            "commandOutputDelta"
        case .followUpSuggestions:
            "followUpSuggestions"
        case .fileChangesUpdated:
            "fileChangesUpdated"
        case .approvalRequested:
            "approvalRequested"
        case .action:
            "action"
        case .turnCompleted:
            "turnCompleted"
        case .accountUpdated:
            "accountUpdated"
        case .accountLoginCompleted:
            "accountLoginCompleted"
        }
    }
}
