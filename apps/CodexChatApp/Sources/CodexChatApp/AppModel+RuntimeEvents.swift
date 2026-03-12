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
        let shouldTrace = shouldTraceRuntimeEventPerformance(event)
        let clock = ContinuousClock()
        let startedAt = shouldTrace ? clock.now : nil
        defer {
            if !unscopedApprovalRequests.isEmpty {
                promoteResolvableUnscopedApprovals()
            }
            if !unscopedServerRequests.isEmpty {
                promoteResolvableUnscopedServerRequests()
            }
        }
        defer {
            if let startedAt {
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

        case let .assistantMessageDelta(assistantDelta):
            guard let localThreadID = resolveLocalThreadID(
                runtimeThreadID: assistantDelta.threadID,
                itemID: assistantDelta.itemID,
                runtimeTurnID: assistantDelta.turnID
            ) else {
                appendLog(.debug, "Dropped delta with no thread mapping")
                return
            }

            if pendingFirstTokenThreadIDs.remove(localThreadID) != nil {
                let performanceSignals = runtimePerformanceSignals
                Task {
                    await performanceSignals.recordFirstTokenIfNeeded(
                        threadID: localThreadID,
                        receivedAt: Date()
                    )
                }
            }

            if assistantDelta.channel == .progress || assistantDelta.channel == .system {
                hasExplicitProgressDeltasByThreadID.insert(localThreadID)
            }

            enqueueAssistantDeltaForUI(
                assistantDelta.delta,
                itemID: assistantDelta.itemID,
                channel: assistantDelta.channel,
                stage: assistantDelta.stage,
                threadID: localThreadID
            )
            if let context = activeTurnContext(for: localThreadID) {
                var payload: [String: String] = [
                    "itemID": assistantDelta.itemID,
                    "delta": assistantDelta.delta,
                    "channel": assistantDelta.channel.rawValue,
                ]
                if let stage = assistantDelta.stage, !stage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    payload["stage"] = stage
                }

                emitExtensionEvent(
                    .assistantDelta,
                    projectID: context.projectID,
                    projectPath: context.projectPath,
                    threadID: context.localThreadID,
                    turnID: context.localTurnID.uuidString,
                    payload: payload
                )
            }
            markThreadUnreadIfNeeded(localThreadID)

        case let .commandOutputDelta(output):
            handleCommandOutputDelta(output)

        case let .fileChangeOutputDelta(output):
            handleFileChangeOutputDelta(output)

        case let .followUpSuggestions(batch):
            handleFollowUpSuggestions(batch)

        case let .fileChangesUpdated(update):
            handleFileChangesUpdate(update)

        case let .serverRequest(request):
            handleServerRequestEvent(request)

        case let .serverRequestResolved(resolution):
            handleServerRequestResolved(resolution)

        case let .approvalRequested(request):
            handleApprovalRequest(request)

        case let .threadStatusUpdated(update):
            handleThreadStatusUpdate(update)

        case let .tokenUsageUpdated(update):
            handleTokenUsageUpdate(update)

        case let .turnDiffUpdated(update):
            handleTurnDiffUpdate(update)

        case let .turnPlanUpdated(update):
            handleTurnPlanUpdate(update)

        case let .modelRerouted(update):
            handleModelRerouted(update)

        case let .runtimeError(update):
            handleRuntimeErrorNotice(update)

        case let .unknownNotification(update):
            appendLog(.warning, "Unknown runtime notification: \(update.method)")

        case let .action(action):
            handleRuntimeAction(action)

        case let .turnCompleted(completion):
            conversationUpdateScheduler.flushImmediately()
            let localThreadID = resolveLocalThreadID(
                runtimeThreadID: completion.threadID,
                itemID: nil,
                runtimeTurnID: completion.turnID
            )
            if let localThreadID {
                pendingFirstTokenThreadIDs.remove(localThreadID)
                let performanceSignals = runtimePerformanceSignals
                Task {
                    await performanceSignals.markTurnCompleted(threadID: localThreadID)
                }
            }

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

                let durability: PersistenceBatcher.Durability = isFailureCompletion(completion) ? .immediate : .batched
                Task {
                    await turnConcurrencyScheduler.release(threadID: context.localThreadID)
                    await persistenceBatcher.enqueue(
                        context: context,
                        completion: completion,
                        durability: durability
                    )
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

    private func shouldTraceRuntimeEventPerformance(_ event: CodexRuntimeEvent) -> Bool {
        switch event {
        case .assistantMessageDelta, .commandOutputDelta:
            runtimeEventTraceSampleCounter = runtimeEventTraceSampleCounter &+ 1
            let sampleRate = max(1, Self.runtimeEventTraceSampleRate)
            return runtimeEventTraceSampleCounter % UInt64(sampleRate) == 0
        default:
            return true
        }
    }

    private func handleRuntimeAction(_ action: RuntimeAction) {
        let classification = TranscriptActionPolicy.classify(
            method: action.method,
            title: action.title,
            detail: action.detail,
            itemType: action.itemType
        )
        let shouldSuppressFromConversation = TranscriptActionPolicy.shouldSuppressRuntimeAction(
            method: action.method,
            title: action.title,
            detail: action.detail
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

        if shouldSuppressFromConversation {
            appendLog(.debug, "Suppressed runtime decode error from transcript: \(action.detail)")
            return
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
            detail: transcriptDetail,
            itemID: action.itemID,
            itemType: action.itemType
        )

        captureWorkerTraceIfPresent(
            runtimeAction: action,
            threadID: localThreadID,
            transcriptDetail: transcriptDetail
        )

        appendEntry(.actionCard(card), to: localThreadID)
        appendSynthesizedProgressNoteIfNeeded(for: card)
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

    private func appendSynthesizedProgressNoteIfNeeded(for card: ActionCard) {
        guard !hasExplicitProgressDeltasByThreadID.contains(card.threadID) else {
            return
        }

        guard let text = synthesizedProgressText(for: card) else {
            return
        }

        let signature = [
            card.method.lowercased(),
            normalizedProgressItemType(for: card) ?? "-",
            text.lowercased(),
        ].joined(separator: "|")

        if synthesizedProgressSignatureByThreadID[card.threadID] == signature {
            return
        }
        synthesizedProgressSignatureByThreadID[card.threadID] = signature

        let itemID = [
            "progress",
            card.itemID ?? UUID().uuidString,
            card.method.lowercased(),
            String(Int(card.createdAt.timeIntervalSinceReferenceDate * 1000)),
        ].joined(separator: ":")

        appendAssistantDelta(
            text,
            itemID: itemID,
            channel: .progress,
            to: card.threadID
        )
    }

    private func synthesizedProgressText(for card: ActionCard) -> String? {
        let method = card.method.lowercased()
        guard method == "item/started" || method == "item/completed" else {
            return nil
        }

        guard let itemType = normalizedProgressItemType(for: card) else {
            return nil
        }

        let started = method == "item/started"
        switch itemType {
        case "reasoning":
            return started ? "Thinking through the approach." : "Reasoning step complete."
        case "websearch":
            return started ? "Searching the web for context." : "Web search complete."
        case "toolcall":
            return started ? "Calling a tool." : "Tool call complete."
        case "commandexecution":
            return started ? "Running a shell command." : "Shell command completed."
        case "filechange":
            return started ? "Preparing file edits." : "File edit step complete."
        default:
            return nil
        }
    }

    private func normalizedProgressItemType(for card: ActionCard) -> String? {
        let normalizedFromItemType = card.itemType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        if let normalizedFromItemType, !normalizedFromItemType.isEmpty {
            return normalizedFromItemType
        }

        let title = card.title.lowercased()
        let titleMappings: [(contains: String, itemType: String)] = [
            ("reasoning", "reasoning"),
            ("websearch", "websearch"),
            ("web search", "websearch"),
            ("toolcall", "toolcall"),
            ("tool call", "toolcall"),
            ("commandexecution", "commandexecution"),
            ("command execution", "commandexecution"),
            ("filechange", "filechange"),
            ("file change", "filechange"),
        ]

        for mapping in titleMappings where title.contains(mapping.contains) {
            return mapping.itemType
        }
        return nil
    }

    private func enqueueAssistantDeltaForUI(
        _ delta: String,
        itemID: String,
        channel: RuntimeAssistantMessageChannel,
        stage: String?,
        threadID: UUID
    ) {
        conversationUpdateScheduler.enqueue(
            delta: delta,
            threadID: threadID,
            itemID: itemID,
            channel: channel,
            stage: stage
        )
    }

    func applyCoalescedAssistantDeltaBatch(_ batch: [ConversationUpdateScheduler.BatchItem]) {
        guard !batch.isEmpty else {
            return
        }

        for item in batch {
            appendAssistantDelta(
                item.delta,
                itemID: item.itemID,
                channel: item.channel,
                stage: item.stage,
                to: item.threadID
            )

            guard item.channel == .finalResponse || item.channel == .unknown else {
                continue
            }

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

    private func handleFileChangeOutputDelta(_ output: RuntimeFileChangeOutputDelta) {
        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: output.threadID,
            itemID: output.itemID,
            runtimeTurnID: output.turnID
        )

        guard let localThreadID else {
            appendLog(.debug, "File change output delta without thread mapping")
            return
        }

        enqueueThreadLog(level: .info, text: output.delta, to: localThreadID)
    }

    private func handleServerRequestEvent(_ request: RuntimeServerRequest) {
        switch request {
        case .approval:
            return
        case .permissions, .userInput, .mcpElicitation, .dynamicToolCall:
            presentServerRequest(request)
        }
    }

    private func appendPendingServerRequestAction(
        threadID: UUID?,
        method: String,
        title: String,
        detail: String
    ) {
        appendLog(.warning, "\(title): \(method)")
        guard let threadID else {
            return
        }

        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: threadID,
                    method: method,
                    title: title,
                    detail: detail
                )
            ),
            to: threadID
        )
        markThreadUnreadIfNeeded(threadID)
    }

    private func handleServerRequestResolved(_ resolution: RuntimeServerRequestResolution) {
        guard let requestID = resolution.requestID else {
            return
        }
        if let request = resolvePendingApprovalRequest(id: requestID) {
            recordRuntimeRequestSupportEvent(
                phase: .resolved,
                summary: runtimeRequestSupportSummary(for: request)
            )
            resolveRuntimeApprovalRequest(
                id: requestID,
                statusMessage: "Runtime resolved request \(requestID)."
            )
        }
        if let request = resolvePendingServerRequest(id: requestID) {
            recordRuntimeRequestSupportEvent(
                phase: .resolved,
                summary: runtimeRequestSupportSummary(for: request)
            )
            resolveRuntimeServerRequest(
                id: requestID,
                statusMessage: "Runtime resolved request \(requestID)."
            )
        }
    }

    private func handleThreadStatusUpdate(_ update: RuntimeThreadStatusUpdate) {
        appendLog(.info, "Runtime thread status changed: \(update.status)")
        guard let localThreadID = resolveLocalThreadID(
            runtimeThreadID: update.threadID,
            itemID: nil,
            runtimeTurnID: nil
        ) else {
            return
        }
        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: localThreadID,
                    method: "thread/status/changed",
                    title: "Thread status changed",
                    detail: update.status
                )
            ),
            to: localThreadID
        )
    }

    private func handleTokenUsageUpdate(_ update: RuntimeTokenUsageUpdate) {
        let parts = [
            update.inputTokens.map { "input=\($0)" },
            update.outputTokens.map { "output=\($0)" },
            update.totalTokens.map { "total=\($0)" },
        ].compactMap(\.self)
        guard !parts.isEmpty else {
            return
        }
        appendLog(.debug, "Runtime token usage updated: \(parts.joined(separator: ", "))")
    }

    private func handleTurnDiffUpdate(_ update: RuntimeTurnDiffUpdate) {
        appendLog(.info, "Runtime turn diff updated")
        guard let diff = update.diff,
              let localThreadID = resolveLocalThreadID(
                  runtimeThreadID: update.threadID,
                  itemID: nil,
                  runtimeTurnID: update.turnID
              )
        else {
            return
        }
        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: localThreadID,
                    method: "turn/diff/updated",
                    title: "Diff updated",
                    detail: diff
                )
            ),
            to: localThreadID
        )
        enqueueThreadLog(level: .info, text: diff, to: localThreadID)
    }

    private func handleTurnPlanUpdate(_ update: RuntimeTurnPlanUpdate) {
        guard let localThreadID = resolveLocalThreadID(
            runtimeThreadID: update.threadID,
            itemID: nil,
            runtimeTurnID: update.turnID
        ) else {
            if let summary = update.summary, !summary.isEmpty {
                appendLog(.info, "Runtime plan updated: \(summary)")
            } else {
                appendLog(.info, "Runtime plan updated")
            }
            return
        }

        let detail = if let summary = update.summary, !summary.isEmpty {
            summary
        } else {
            "The runtime updated its plan."
        }
        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: localThreadID,
                    method: "turn/plan/updated",
                    title: "Plan updated",
                    detail: detail
                )
            ),
            to: localThreadID
        )
        if let summary = update.summary, !summary.isEmpty {
            appendLog(.info, "Runtime plan updated: \(summary)")
        } else {
            appendLog(.info, "Runtime plan updated")
        }
    }

    private func handleModelRerouted(_ update: RuntimeModelReroute) {
        let fromModel = update.fromModel ?? "unknown"
        let toModel = update.toModel ?? "unknown"
        appendLog(.warning, "Runtime rerouted model from \(fromModel) to \(toModel).")
        guard let localThreadID = resolveLocalThreadID(
            runtimeThreadID: update.threadID,
            itemID: nil,
            runtimeTurnID: update.turnID
        ) else {
            return
        }
        let reason = update.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = if let reason, !reason.isEmpty {
            "\(fromModel) -> \(toModel) • \(reason)"
        } else {
            "\(fromModel) -> \(toModel)"
        }
        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: localThreadID,
                    method: "model/rerouted",
                    title: "Model rerouted",
                    detail: detail
                )
            ),
            to: localThreadID
        )
    }

    private func handleRuntimeErrorNotice(_ update: RuntimeErrorNotice) {
        let detail = [update.code, update.message].compactMap(\.self).joined(separator: ": ")
        appendLog(.error, "Runtime error: \(detail)")
        guard let localThreadID = resolveLocalThreadID(
            runtimeThreadID: update.threadID,
            itemID: update.itemID,
            runtimeTurnID: update.turnID
        ) else {
            return
        }
        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: localThreadID,
                    method: "error",
                    title: "Runtime error",
                    detail: detail
                )
            ),
            to: localThreadID
        )
    }

    private func handleApprovalRequest(_ request: RuntimeApprovalRequest) {
        approvalStatusMessage = nil

        let resolvedLocalThreadID = resolveLocalThreadID(
            runtimeThreadID: request.threadID,
            itemID: request.itemID,
            runtimeTurnID: request.turnID
        )
        let localThreadID = resolvedLocalThreadID ?? fallbackLocalThreadIDForUnscopedApproval(request)

        if shouldAutoApproveTrustedHarnessCommand(request) {
            autoApproveTrustedHarnessCommand(request, localThreadID: localThreadID)
            return
        }

        guard let localThreadID else {
            if !unscopedApprovalRequests.contains(where: { $0.id == request.id }) {
                unscopedApprovalRequests.append(request)
            }
            syncApprovalPresentationState()
            recordRuntimeRequestSupportEvent(
                phase: .requested,
                summary: runtimeRequestSupportSummary(for: request)
            )
            appendLog(.warning, "Approval request arrived without local thread mapping")
            return
        }

        presentApprovalRequest(request, localThreadID: localThreadID)
    }

    func shouldAutoApproveTrustedHarnessCommand(_ request: RuntimeApprovalRequest) -> Bool {
        guard request.kind == .commandExecution else {
            return false
        }
        guard let environment = effectiveComputerActionHarnessEnvironment() else {
            return false
        }
        let command = request.command
        guard command.count == 8 else {
            return false
        }
        guard command[0] == environment.wrapperPath,
              command[1] == "invoke",
              command[2] == "--run-token",
              !command[3].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              command[4] == "--action-id",
              !command[5].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              command[6] == "--arguments-json",
              !command[7].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }
        return true
    }

    private func autoApproveTrustedHarnessCommand(_ request: RuntimeApprovalRequest, localThreadID: UUID?) {
        guard let runtimePool else {
            if let localThreadID {
                presentApprovalRequest(request, localThreadID: localThreadID)
            } else if !unscopedApprovalRequests.contains(where: { $0.id == request.id }) {
                unscopedApprovalRequests.append(request)
                syncApprovalPresentationState()
            }
            return
        }

        appendLog(.info, "Auto-approving trusted computer action harness command approval \(request.id).")
        if let localThreadID {
            appendEntry(
                .actionCard(
                    ActionCard(
                        threadID: localThreadID,
                        method: request.method,
                        title: "Trusted harness command auto-approved",
                        detail: approvalSummary(for: request)
                    )
                ),
                to: localThreadID
            )
            markThreadUnreadIfNeeded(localThreadID)
        }

        Task {
            do {
                try await runtimePool.respondToApproval(requestID: request.id, decision: .approveOnce)
                requestAutoDrain(reason: "trusted harness command approved")
            } catch {
                appendLog(.warning, "Trusted harness auto-approval failed (\(request.id)): \(error.localizedDescription)")
                if let localThreadID {
                    presentApprovalRequest(request, localThreadID: localThreadID)
                } else if !unscopedApprovalRequests.contains(where: { $0.id == request.id }) {
                    unscopedApprovalRequests.append(request)
                }
                syncApprovalPresentationState()
            }
        }
    }

    private func presentApprovalRequest(_ request: RuntimeApprovalRequest, localThreadID: UUID) {
        approvalStateMachine.enqueue(request, threadID: localThreadID)
        syncApprovalPresentationState()
        recordRuntimeRequestSupportEvent(
            phase: .requested,
            summary: runtimeRequestSupportSummary(for: request, localThreadID: localThreadID)
        )

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

    private func promoteResolvableUnscopedApprovals() {
        guard !unscopedApprovalRequests.isEmpty else {
            return
        }

        var unresolved: [RuntimeApprovalRequest] = []
        unresolved.reserveCapacity(unscopedApprovalRequests.count)

        for request in unscopedApprovalRequests {
            let localThreadID = resolveLocalThreadID(
                runtimeThreadID: request.threadID,
                itemID: request.itemID,
                runtimeTurnID: request.turnID
            ) ?? fallbackLocalThreadIDForUnscopedApproval(request)

            guard let localThreadID else {
                unresolved.append(request)
                continue
            }

            presentApprovalRequest(request, localThreadID: localThreadID)
        }

        if unresolved.count != unscopedApprovalRequests.count {
            unscopedApprovalRequests = unresolved
            syncApprovalPresentationState()
        }
    }

    private func presentServerRequest(_ request: RuntimeServerRequest) {
        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: runtimeThreadID(for: request),
            itemID: itemID(for: request),
            runtimeTurnID: runtimeTurnID(for: request)
        ) ?? fallbackLocalThreadIDForUnscopedServerRequest(request)

        let summary = serverRequestSummary(for: request)
        if let localThreadID {
            serverRequestStateMachine.enqueue(request, threadID: localThreadID)
            syncApprovalPresentationState()
            recordRuntimeRequestSupportEvent(
                phase: .requested,
                summary: runtimeRequestSupportSummary(for: request, localThreadID: localThreadID)
            )
            appendPendingServerRequestAction(
                threadID: localThreadID,
                method: request.method,
                title: summary.title,
                detail: summary.detail
            )
            return
        }

        if !unscopedServerRequests.contains(where: { $0.id == request.id }) {
            unscopedServerRequests.append(request)
            syncApprovalPresentationState()
            recordRuntimeRequestSupportEvent(
                phase: .requested,
                summary: runtimeRequestSupportSummary(for: request)
            )
        }
        appendLog(.warning, "\(summary.title) arrived without local thread mapping")
    }

    private func promoteResolvableUnscopedServerRequests() {
        guard !unscopedServerRequests.isEmpty else {
            return
        }

        var unresolved: [RuntimeServerRequest] = []
        unresolved.reserveCapacity(unscopedServerRequests.count)

        for request in unscopedServerRequests {
            let localThreadID = resolveLocalThreadID(
                runtimeThreadID: runtimeThreadID(for: request),
                itemID: itemID(for: request),
                runtimeTurnID: runtimeTurnID(for: request)
            ) ?? fallbackLocalThreadIDForUnscopedServerRequest(request)

            guard let localThreadID else {
                unresolved.append(request)
                continue
            }

            serverRequestStateMachine.enqueue(request, threadID: localThreadID)
        }

        if unresolved.count != unscopedServerRequests.count {
            unscopedServerRequests = unresolved
            syncApprovalPresentationState()
        }
    }

    private func runtimeThreadID(for request: RuntimeServerRequest) -> String? {
        switch request {
        case let .approval(approval):
            approval.threadID
        case let .permissions(permission):
            permission.threadID
        case let .userInput(userInput):
            userInput.threadID
        case let .mcpElicitation(mcp):
            mcp.threadID
        case let .dynamicToolCall(tool):
            tool.threadID
        }
    }

    private func runtimeTurnID(for request: RuntimeServerRequest) -> String? {
        switch request {
        case let .approval(approval):
            approval.turnID
        case let .permissions(permission):
            permission.turnID
        case let .userInput(userInput):
            userInput.turnID
        case let .mcpElicitation(mcp):
            mcp.turnID
        case let .dynamicToolCall(tool):
            tool.turnID
        }
    }

    private func itemID(for request: RuntimeServerRequest) -> String? {
        switch request {
        case let .approval(approval):
            approval.itemID
        case let .permissions(permission):
            permission.itemID
        case let .userInput(userInput):
            userInput.itemID
        case let .mcpElicitation(mcp):
            mcp.itemID
        case let .dynamicToolCall(tool):
            tool.itemID
        }
    }

    private func fallbackLocalThreadIDForUnscopedServerRequest(_ request: RuntimeServerRequest) -> UUID? {
        guard runtimeThreadID(for: request) == nil,
              runtimeTurnID(for: request) == nil,
              itemID(for: request) == nil,
              activeTurnContextsByThreadID.count == 1
        else {
            return nil
        }

        return activeTurnContextsByThreadID.first?.key
    }

    private func serverRequestSummary(for request: RuntimeServerRequest) -> (title: String, detail: String) {
        switch request {
        case let .permissions(permission):
            ("Permission request pending", permission.detail)
        case let .userInput(userInput):
            ("Input request pending", userInput.detail)
        case let .mcpElicitation(mcp):
            ("MCP elicitation pending", mcp.detail)
        case let .dynamicToolCall(tool):
            ("Dynamic tool call requested", tool.detail)
        case let .approval(approval):
            ("Approval request pending", approval.detail)
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

        if let runtimeTurnID,
           let mappedContext = activeTurnContextsByThreadID.values.first(where: { $0.runtimeTurnID == runtimeTurnID })
        {
            return mappedContext.localThreadID
        }

        if let runtimeThreadID {
            if let mapped = localThreadIDByRuntimeThreadID[runtimeThreadID] {
                return mapped
            }

            if let mappedContext = activeTurnContextsByThreadID.values.first(where: { $0.runtimeThreadID == runtimeThreadID }) {
                return mappedContext.localThreadID
            }
        }

        if runtimeThreadID == nil,
           itemID == nil,
           runtimeTurnID == nil,
           activeTurnContextsByThreadID.count == 1
        {
            return activeTurnContextsByThreadID.first?.key
        }

        return nil
    }

    private func fallbackLocalThreadIDForUnscopedApproval(_ request: RuntimeApprovalRequest) -> UUID? {
        guard request.threadID == nil,
              request.turnID == nil,
              request.itemID == nil,
              activeTurnContextsByThreadID.count == 1
        else {
            return nil
        }
        return activeTurnContextsByThreadID.first?.key
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
                    title: "Inspect Shared Codex Home",
                    detail: "Runtime reported missing rollout path metadata. Open Settings > Storage to inspect the active shared Codex home path."
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
        case .fileChangeOutputDelta:
            "fileChangeOutputDelta"
        case .followUpSuggestions:
            "followUpSuggestions"
        case .fileChangesUpdated:
            "fileChangesUpdated"
        case .serverRequest:
            "serverRequest"
        case .serverRequestResolved:
            "serverRequestResolved"
        case .approvalRequested:
            "approvalRequested"
        case .threadStatusUpdated:
            "threadStatusUpdated"
        case .tokenUsageUpdated:
            "tokenUsageUpdated"
        case .turnDiffUpdated:
            "turnDiffUpdated"
        case .turnPlanUpdated:
            "turnPlanUpdated"
        case .modelRerouted:
            "modelRerouted"
        case .runtimeError:
            "runtimeError"
        case .unknownNotification:
            "unknownNotification"
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
