import CodexChatCore
import CodexKit
import Foundation

extension AppModel {
    func submitComposerWithQueuePolicy() {
        let trimmedText = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = composerAttachments
        guard !trimmedText.isEmpty || !attachments.isEmpty else {
            return
        }

        if maybeHandleAdaptiveIntentFromComposer(
            text: trimmedText,
            attachments: attachments
        ) {
            composerText = ""
            clearComposerAttachments()
            return
        }

        let startedFromDraft = hasActiveDraftChatForSelectedProject
        let initialPolicy = composerDispatchPolicy
        if attachments.isEmpty == false, case .queueOnly = initialPolicy {
            followUpStatusMessage = "Attachments can't be queued while a turn is running. Wait for idle, then send."
            return
        }

        if case let .disabled(reason) = initialPolicy {
            followUpStatusMessage = reason
            return
        }

        let pendingThreadID: UUID? = {
            guard case .readyNow = initialPolicy else {
                return nil
            }
            return selectedThreadID
        }()
        if let pendingThreadID {
            markTurnStartPending(threadID: pendingThreadID)
        }

        composerText = ""
        clearComposerAttachments()

        Task {
            do {
                let threadID = try await materializeDraftThreadIfNeeded()
                let dispatchPolicy = startedFromDraft ? composerDispatchPolicy : initialPolicy

                switch dispatchPolicy {
                case .readyNow:
                    do {
                        let (_, project) = try await resolveProjectAndThread(for: threadID)
                        try await dispatchNow(
                            text: trimmedText,
                            threadID: threadID,
                            projectID: project.id,
                            projectPath: project.path,
                            sourceQueueItemID: nil,
                            priority: .selected,
                            composerAttachments: attachments
                        )
                    } catch {
                        throw error
                    }

                case .queueOnly:
                    guard attachments.isEmpty else {
                        composerText = trimmedText
                        composerAttachments = attachments
                        followUpStatusMessage = "Attachments can't be queued while a turn is running. Wait for idle, then send."
                        return
                    }
                    try await enqueueFollowUp(
                        threadID: threadID,
                        text: trimmedText,
                        source: .userQueued,
                        dispatchMode: .auto
                    )
                    followUpStatusMessage = "Queued follow-up. It will auto-send when the runtime is idle."
                    requestAutoDrain(reason: "composer queued")

                case let .disabled(reason):
                    followUpStatusMessage = reason
                }
            } catch {
                if let pendingThreadID {
                    clearTurnStartPending(threadID: pendingThreadID)
                }
                followUpStatusMessage = "Failed to send follow-up: \(error.localizedDescription)"
                appendLog(.error, "Composer dispatch failed: \(error.localizedDescription)")
            }
        }
    }

    func steerFollowUp(_ itemID: UUID) {
        Task {
            await steerFollowUpAsync(itemID)
        }
    }

    func deleteFollowUp(_ itemID: UUID) {
        Task {
            do {
                guard let item = followUpItem(id: itemID),
                      let followUpQueueRepository
                else {
                    return
                }
                try await followUpQueueRepository.delete(id: itemID)
                try await refreshFollowUpQueue(threadID: item.threadID)
                requestAutoDrain(reason: "follow-up deleted")
            } catch {
                followUpStatusMessage = "Failed to delete follow-up: \(error.localizedDescription)"
                appendLog(.error, "Delete follow-up failed: \(error.localizedDescription)")
            }
        }
    }

    func moveFollowUpUp(_ itemID: UUID) {
        moveFollowUp(itemID, offset: -1)
    }

    func moveFollowUpDown(_ itemID: UUID) {
        moveFollowUp(itemID, offset: 1)
    }

    func setFollowUpDispatchMode(_ mode: FollowUpDispatchMode, for itemID: UUID) {
        Task {
            do {
                guard let item = followUpItem(id: itemID),
                      let followUpQueueRepository
                else {
                    return
                }
                _ = try await followUpQueueRepository.updateDispatchMode(id: itemID, mode: mode)
                try await refreshFollowUpQueue(threadID: item.threadID)
                requestAutoDrain(reason: "follow-up mode updated")
            } catch {
                followUpStatusMessage = "Failed to update follow-up mode: \(error.localizedDescription)"
                appendLog(.error, "Update follow-up mode failed: \(error.localizedDescription)")
            }
        }
    }

    func updateFollowUpText(_ text: String, id itemID: UUID) {
        Task {
            do {
                guard let item = followUpItem(id: itemID),
                      let followUpQueueRepository
                else {
                    return
                }
                _ = try await followUpQueueRepository.updateText(
                    id: itemID,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                try await refreshFollowUpQueue(threadID: item.threadID)
                requestAutoDrain(reason: "follow-up text updated")
            } catch {
                followUpStatusMessage = "Failed to update follow-up: \(error.localizedDescription)"
                appendLog(.error, "Update follow-up text failed: \(error.localizedDescription)")
            }
        }
    }

    func retryFailedFollowUp(_ itemID: UUID) {
        Task {
            do {
                guard let item = followUpItem(id: itemID),
                      let followUpQueueRepository
                else {
                    return
                }
                try await followUpQueueRepository.markPending(id: itemID)
                _ = try await followUpQueueRepository.updateDispatchMode(id: itemID, mode: .auto)
                try await followUpQueueRepository.move(id: itemID, threadID: item.threadID, toSortIndex: 0)
                try await refreshFollowUpQueue(threadID: item.threadID)
                requestAutoDrain(reason: "retry failed follow-up")
            } catch {
                followUpStatusMessage = "Failed to retry follow-up: \(error.localizedDescription)"
                appendLog(.error, "Retry follow-up failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshFollowUpQueuesForVisibleThreads() async throws {
        let threadIDs = Set((threads + generalThreads).map(\.id) + [selectedThreadID].compactMap(\.self))
        for threadID in threadIDs {
            try await refreshFollowUpQueue(threadID: threadID)
        }
    }

    func refreshFollowUpQueue(threadID: UUID) async throws {
        guard let followUpQueueRepository else {
            followUpQueueByThreadID[threadID] = []
            return
        }

        let items = try await followUpQueueRepository.list(threadID: threadID)
        followUpQueueByThreadID[threadID] = items
    }

    func handleFollowUpSuggestions(_ batch: RuntimeFollowUpSuggestionBatch) {
        guard runtimeCapabilities.supportsFollowUpSuggestions else {
            return
        }

        Task {
            guard let localThreadID = resolveLocalThreadID(
                runtimeThreadID: batch.threadID,
                itemID: nil,
                runtimeTurnID: batch.turnID
            )
            else {
                appendLog(.debug, "Dropped follow-up suggestions with no thread mapping")
                return
            }

            var addedCount = 0
            for suggestion in batch.suggestions.sorted(by: { compareSuggestions($0, $1) }) {
                do {
                    try await enqueueFollowUp(
                        threadID: localThreadID,
                        text: suggestion.text,
                        source: .assistantSuggestion,
                        dispatchMode: .manual,
                        originTurnID: batch.turnID,
                        originSuggestionID: suggestion.id
                    )
                    addedCount += 1
                } catch {
                    if !isDuplicateSuggestionError(error) {
                        appendLog(.warning, "Failed to enqueue suggestion: \(error.localizedDescription)")
                    }
                }
            }

            if addedCount > 0 {
                followUpStatusMessage = "Added \(addedCount) suggested follow-up\(addedCount == 1 ? "" : "s")."
            }
        }
    }

    func requestAutoDrain(reason: String) {
        guard followUpDrainTask == nil else {
            pendingFollowUpAutoDrainReason = reason
            return
        }

        followUpDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                followUpDrainTask = nil
                pendingFollowUpAutoDrainReason = nil
            }

            var nextReason: String? = reason
            while let reasonToDrain = nextReason {
                pendingFollowUpAutoDrainReason = nil
                await drainAutoFollowUpsUntilBusy(reason: reasonToDrain)
                nextReason = pendingFollowUpAutoDrainReason
            }
        }
    }

    private var composerDispatchPolicy: ComposerDispatchPolicy {
        guard canSubmitComposer else {
            return .disabled(composerDisabledReason())
        }

        if canDispatchSelectedThreadImmediately {
            return .readyNow
        }

        return .queueOnly
    }

    private func moveFollowUp(_ itemID: UUID, offset: Int) {
        Task {
            do {
                guard let item = followUpItem(id: itemID),
                      let followUpQueueRepository
                else {
                    return
                }

                let queue = followUpQueueByThreadID[item.threadID, default: []]
                guard let currentIndex = queue.firstIndex(where: { $0.id == itemID }) else {
                    return
                }

                let nextIndex = max(0, min(queue.count - 1, currentIndex + offset))
                guard nextIndex != currentIndex else {
                    return
                }

                try await followUpQueueRepository.move(id: itemID, threadID: item.threadID, toSortIndex: nextIndex)
                try await refreshFollowUpQueue(threadID: item.threadID)
                requestAutoDrain(reason: "follow-up re-prioritized")
            } catch {
                followUpStatusMessage = "Failed to reorder follow-up: \(error.localizedDescription)"
                appendLog(.error, "Reorder follow-up failed: \(error.localizedDescription)")
            }
        }
    }

    private func steerFollowUpAsync(_ itemID: UUID) async {
        guard let item = followUpItem(id: itemID) else {
            return
        }

        guard let followUpQueueRepository else {
            followUpStatusMessage = "Follow-up queue is unavailable."
            appendLog(.error, "Follow-up queue repository is unavailable while steering follow-up")
            return
        }

        if let activeTurnContext = activeTurnContext(for: item.threadID) {
            guard runtimeCapabilities.supportsTurnSteer,
                  let runtime
            else {
                await fallbackSteerToQueuedAuto(item)
                return
            }

            guard let runtimeTurnID = activeTurnContext.runtimeTurnID,
                  !runtimeTurnID.isEmpty
            else {
                appendLog(.warning, "Active turn is missing a runtime turn ID. Falling back to queued dispatch.")
                await fallbackSteerToQueuedAuto(item)
                return
            }

            do {
                try await runtime.steerTurn(
                    threadID: activeTurnContext.runtimeThreadID,
                    text: item.text,
                    expectedTurnID: runtimeTurnID
                )
                try await followUpQueueRepository.delete(id: itemID)
                try await refreshFollowUpQueue(threadID: item.threadID)
                followUpStatusMessage = "Steered follow-up into the active turn."
            } catch let error as CodexRuntimeError where isUnsupportedSteerError(error) {
                runtimeCapabilities.supportsTurnSteer = false
                appendLog(.warning, "Runtime does not support turn/steer. Falling back to queued dispatch.")
                await fallbackSteerToQueuedAuto(item)
            } catch {
                do {
                    try await followUpQueueRepository.markFailed(id: itemID, error: error.localizedDescription)
                    try await refreshFollowUpQueue(threadID: item.threadID)
                } catch {
                    appendLog(.warning, "Failed to mark follow-up failure after steer error: \(error.localizedDescription)")
                }
                followUpStatusMessage = "Failed to steer follow-up: \(error.localizedDescription)"
            }
            return
        }

        do {
            let (_, project) = try await resolveProjectAndThread(for: item.threadID)
            try await dispatchNow(
                text: item.text,
                threadID: item.threadID,
                projectID: project.id,
                projectPath: project.path,
                sourceQueueItemID: item.id,
                priority: .manual
            )
        } catch {
            do {
                try await followUpQueueRepository.markFailed(id: item.id, error: error.localizedDescription)
                try await refreshFollowUpQueue(threadID: item.threadID)
            } catch {
                appendLog(.warning, "Failed to persist follow-up failure: \(error.localizedDescription)")
            }
            followUpStatusMessage = "Failed to send follow-up: \(error.localizedDescription)"
        }
    }

    private func fallbackSteerToQueuedAuto(_ item: FollowUpQueueItemRecord) async {
        do {
            guard let followUpQueueRepository else { return }
            _ = try await followUpQueueRepository.updateDispatchMode(id: item.id, mode: .auto)
            try await followUpQueueRepository.markPending(id: item.id)
            try await followUpQueueRepository.move(id: item.id, threadID: item.threadID, toSortIndex: 0)
            try await refreshFollowUpQueue(threadID: item.threadID)
            followUpStatusMessage = "Steer is unavailable while busy. Queued this follow-up to send next."
            requestAutoDrain(reason: "steer fallback")
        } catch {
            followUpStatusMessage = "Failed to queue follow-up for next send: \(error.localizedDescription)"
            appendLog(.error, "Failed steer fallback queueing: \(error.localizedDescription)")
        }
    }

    private func drainAutoFollowUpsUntilBusy(reason: String) async {
        while canDispatchNowForQueue {
            let dispatched = await drainOneAutoFollowUp(reason: reason)
            if !dispatched {
                break
            }
        }
    }

    @discardableResult
    private func drainOneAutoFollowUp(reason: String) async -> Bool {
        guard canDispatchNowForQueue else {
            return false
        }

        guard let followUpQueueRepository else {
            return false
        }

        var activeCandidate: FollowUpQueueItemRecord?
        do {
            let blockedThreadIDs = activeTurnThreadIDs
            guard let candidate = try await followUpQueueRepository.listNextAutoCandidate(
                preferredThreadID: autoDrainPreferredThreadID,
                excludingThreadIDs: blockedThreadIDs
            ) else {
                return false
            }
            activeCandidate = candidate

            let (_, project) = try await resolveProjectAndThread(for: candidate.threadID)
            autoDrainPreferredThreadID = candidate.threadID
            try await dispatchNow(
                text: candidate.text,
                threadID: candidate.threadID,
                projectID: project.id,
                projectPath: project.path,
                sourceQueueItemID: candidate.id,
                priority: candidate.threadID == selectedThreadID ? .selected : .queuedAuto
            )
            appendLog(.debug, "Auto-dispatched queued follow-up (\(reason))")
            return true
        } catch {
            do {
                if let candidate = activeCandidate {
                    try await followUpQueueRepository.markFailed(id: candidate.id, error: error.localizedDescription)
                    try await refreshFollowUpQueue(threadID: candidate.threadID)
                }
            } catch {
                appendLog(.warning, "Failed to persist follow-up queue failure: \(error.localizedDescription)")
            }

            followUpStatusMessage = "Queued follow-up failed to start: \(error.localizedDescription)"
            appendLog(.error, "Auto-drain failed: \(error.localizedDescription)")
            return false
        }
    }

    private func enqueueFollowUp(
        threadID: UUID,
        text: String,
        source: FollowUpSource,
        dispatchMode: FollowUpDispatchMode,
        originTurnID: String? = nil,
        originSuggestionID: String? = nil
    ) async throws {
        guard let followUpQueueRepository else {
            throw CodexRuntimeError.invalidResponse("Follow-up queue repository is unavailable.")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let existing: [FollowUpQueueItemRecord] = if let cached = followUpQueueByThreadID[threadID] {
            cached
        } else {
            try await followUpQueueRepository.list(threadID: threadID)
        }
        let item = FollowUpQueueItemRecord(
            threadID: threadID,
            source: source,
            dispatchMode: dispatchMode,
            state: .pending,
            text: trimmed,
            sortIndex: existing.count,
            originTurnID: originTurnID,
            originSuggestionID: originSuggestionID
        )
        try await followUpQueueRepository.enqueue(item)
        try await refreshFollowUpQueue(threadID: threadID)
    }

    private func resolveProjectAndThread(for threadID: UUID) async throws -> (ThreadRecord, ProjectRecord) {
        guard let threadRepository else {
            throw CodexRuntimeError.invalidResponse("Thread repository is unavailable.")
        }
        guard let projectRepository else {
            throw CodexRuntimeError.invalidResponse("Project repository is unavailable.")
        }

        guard let thread = try await threadRepository.getThread(id: threadID) else {
            throw CodexChatCoreError.missingRecord(threadID.uuidString)
        }
        guard let project = try await projectRepository.getProject(id: thread.projectId) else {
            throw CodexChatCoreError.missingRecord(thread.projectId.uuidString)
        }

        return (thread, project)
    }

    private var canDispatchNowForQueue: Bool {
        runtime != nil
            && runtimeIssue == nil
            && runtimeStatus == .connected
            && pendingModReview == nil
            && !isModReviewDecisionInProgress
            && activeTurnThreadIDs.count < AppModel.defaultMaxConcurrentTurns
            && isSignedInForRuntime
    }

    private var canDispatchSelectedThreadImmediately: Bool {
        selectedThreadID != nil
            && selectedProjectID != nil
            && runtime != nil
            && runtimeIssue == nil
            && runtimeStatus == .connected
            && pendingModReview == nil
            && !hasPendingApprovalForSelectedThread
            && !isSelectedThreadApprovalInProgress
            && !isModReviewDecisionInProgress
            && !isSelectedThreadWorking
            && activeTurnThreadIDs.count < AppModel.defaultMaxConcurrentTurns
            && isSignedInForRuntime
    }

    private func followUpItem(id: UUID) -> FollowUpQueueItemRecord? {
        for items in followUpQueueByThreadID.values {
            if let item = items.first(where: { $0.id == id }) {
                return item
            }
        }
        return nil
    }

    private func compareSuggestions(_ lhs: RuntimeFollowUpSuggestion, _ rhs: RuntimeFollowUpSuggestion) -> Bool {
        switch (lhs.priority, rhs.priority) {
        case let (leftPriority?, rightPriority?):
            if leftPriority != rightPriority { return leftPriority < rightPriority }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        return lhs.text.localizedCaseInsensitiveCompare(rhs.text) == .orderedAscending
    }

    private func isDuplicateSuggestionError(_ error: Error) -> Bool {
        let detail = error.localizedDescription.lowercased()
        return detail.contains("unique")
            || detail.contains("constraint")
            || detail.contains("originSuggestionID".lowercased())
    }

    private func isUnsupportedSteerError(_ error: CodexRuntimeError) -> Bool {
        guard case let .rpcError(code, message) = error else {
            return false
        }
        let lowered = message.lowercased()
        let invalidRequestSchemaMismatch = code == -32600
            && (
                lowered.contains("invalid request")
                    || lowered.contains("missing field")
                    || lowered.contains("unknown field")
                    || lowered.contains("invalid type")
            )
        return code == -32601
            || invalidRequestSchemaMismatch
            || lowered.contains("method not found")
            || lowered.contains("unsupported")
    }

    private func composerDisabledReason() -> String {
        if runtimeStatus != .connected {
            return "Runtime is not connected yet."
        }
        if runtimeIssue != nil {
            return "Runtime is unavailable. Resolve runtime errors and retry."
        }
        if pendingModReview != nil {
            return "Resolve pending mod review before sending follow-ups."
        }
        if hasPendingApprovalForSelectedThread || isSelectedThreadApprovalInProgress {
            return "Resolve pending approval before sending follow-ups."
        }
        if isModReviewDecisionInProgress {
            return "Wait for mod review decision to finish."
        }
        if !isSignedInForRuntime {
            return "Sign in to the runtime before sending follow-ups."
        }
        return "Select a thread to send follow-ups."
    }
}

private enum ComposerDispatchPolicy {
    case readyNow
    case queueOnly
    case disabled(String)
}
