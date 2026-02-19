import AppKit
import CodexChatCore
import CodexKit
import Foundation

extension AppModel {
    func installCodexWithHomebrew() {
        do {
            try CodexRuntime.launchCodexInstallInTerminal()
            runtimeSetupMessage = "Opened Terminal and started Codex install. When it finishes, click Restart Runtime."
            appendLog(.info, "Launched Codex install command in Terminal")
        } catch {
            runtimeSetupMessage = "Unable to start Codex install automatically: \(error.localizedDescription)"
            appendLog(.error, "Failed to launch Codex install command: \(error.localizedDescription)")
        }
    }

    func copyCodexInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(CodexRuntime.codexInstallCommand, forType: .string)
        runtimeSetupMessage = "Copied install command to clipboard: \(CodexRuntime.codexInstallCommand)"
        appendLog(.debug, "Copied Codex install command to clipboard")
    }

    func sendMessage() {
        submitComposerWithQueuePolicy()
    }

    func dispatchNow(
        text: String,
        threadID: UUID,
        projectID: UUID,
        projectPath: String,
        sourceQueueItemID: UUID?,
        composerAttachments: [ComposerAttachment] = []
    ) async throws {
        guard let runtime else {
            throw CodexRuntimeError.processNotRunning
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !composerAttachments.isEmpty else {
            return
        }

        let displayText = displayTextForComposerSubmission(text: trimmedText, attachments: composerAttachments)
        let runtimeText = runtimeTextForComposerSubmission(text: trimmedText, attachments: composerAttachments)
        let inputItems = runtimeInputItemsForComposerAttachments(composerAttachments)

        appendEntry(.message(ChatMessage(threadId: threadID, role: .user, text: displayText)), to: threadID)
        followUpStatusMessage = nil
        isTurnInProgress = true
        autoDrainPreferredThreadID = threadID

        guard let project = try await projectRepository?.getProject(id: projectID) else {
            throw CodexChatCoreError.missingRecord(projectID.uuidString)
        }

        let effectiveMemoryWriteMode = effectiveComposerMemoryWriteMode(for: project)
        let safetyConfiguration = runtimeSafetyConfiguration(
            for: project,
            preferredWebSearch: defaultWebSearch
        )
        let turnOptions = runtimeTurnOptions()
        let selectedSkillInput: RuntimeSkillInput? = sourceQueueItemID == nil ? selectedSkillForComposer.map {
            RuntimeSkillInput(name: $0.skill.name, path: $0.skill.skillPath)
        } : nil

        do {
            var runtimeThreadID = try await ensureRuntimeThreadID(
                for: threadID,
                projectPath: projectPath,
                safetyConfiguration: safetyConfiguration
            )
            let startedAt = Date()
            let localTurnID = UUID()
            activeTurnContext = ActiveTurnContext(
                localTurnID: localTurnID,
                localThreadID: threadID,
                projectID: projectID,
                projectPath: projectPath,
                runtimeThreadID: runtimeThreadID,
                memoryWriteMode: effectiveMemoryWriteMode,
                userText: displayText,
                assistantText: "",
                actions: [],
                startedAt: startedAt
            )

            do {
                _ = try ChatArchiveStore.beginCheckpoint(
                    projectPath: projectPath,
                    threadID: threadID,
                    turn: ArchivedTurnSummary(
                        turnID: localTurnID,
                        timestamp: startedAt,
                        status: .pending,
                        userText: displayText,
                        assistantText: "",
                        actions: []
                    )
                )
            } catch {
                appendLog(.warning, "Failed to checkpoint turn start: \(error.localizedDescription)")
            }

            activeModSnapshot = {
                do {
                    return try captureModSnapshot(
                        projectPath: projectPath,
                        threadID: threadID,
                        startedAt: startedAt
                    )
                } catch {
                    appendLog(.warning, "Failed to capture mod snapshot: \(error.localizedDescription)")
                    return nil
                }
            }()

            let turnID: String
            do {
                turnID = try await startTurnWithRuntimeFallback(
                    runtime: runtime,
                    threadID: runtimeThreadID,
                    text: runtimeText,
                    safetyConfiguration: safetyConfiguration,
                    skillInputs: selectedSkillInput.map { [$0] } ?? [],
                    inputItems: inputItems,
                    turnOptions: turnOptions
                )
            } catch {
                guard shouldRecreateRuntimeThread(after: error) else {
                    throw error
                }

                appendLog(.warning, "Runtime thread \(runtimeThreadID) appears stale. Creating a new runtime thread and retrying.")
                invalidateRuntimeThreadID(for: threadID)
                runtimeThreadID = try await createAndPersistRuntimeThreadID(
                    for: threadID,
                    projectPath: projectPath,
                    safetyConfiguration: safetyConfiguration
                )

                if var context = activeTurnContext,
                   context.localThreadID == threadID
                {
                    context.runtimeThreadID = runtimeThreadID
                    activeTurnContext = context
                }

                turnID = try await startTurnWithRuntimeFallback(
                    runtime: runtime,
                    threadID: runtimeThreadID,
                    text: runtimeText,
                    safetyConfiguration: safetyConfiguration,
                    skillInputs: selectedSkillInput.map { [$0] } ?? [],
                    inputItems: inputItems,
                    turnOptions: turnOptions
                )
            }

            if var context = activeTurnContext,
               context.localThreadID == threadID
            {
                context.runtimeTurnID = turnID
                activeTurnContext = context
            }

            if let sourceQueueItemID {
                do {
                    guard let followUpQueueRepository else {
                        throw CodexRuntimeError.invalidResponse("Follow-up queue repository is unavailable.")
                    }
                    try await followUpQueueRepository.delete(id: sourceQueueItemID)
                    try await refreshFollowUpQueue(threadID: threadID)
                } catch {
                    appendLog(.warning, "Turn started but failed to remove queued follow-up \(sourceQueueItemID): \(error.localizedDescription)")
                }
            }

            appendLog(.info, "Started turn \(turnID) for local thread \(threadID.uuidString)")
        } catch {
            if let context = activeTurnContext,
               context.localThreadID == threadID
            {
                let failureAction = ActionCard(
                    threadID: threadID,
                    method: "turn/start/error",
                    title: "Turn failed to start",
                    detail: error.localizedDescription,
                    createdAt: Date()
                )
                do {
                    _ = try ChatArchiveStore.failCheckpoint(
                        projectPath: projectPath,
                        threadID: threadID,
                        turn: ArchivedTurnSummary(
                            turnID: context.localTurnID,
                            timestamp: context.startedAt,
                            status: .failed,
                            userText: context.userText,
                            assistantText: context.assistantText,
                            actions: context.actions + [failureAction]
                        )
                    )
                } catch {
                    appendLog(.warning, "Failed to persist failed turn checkpoint: \(error.localizedDescription)")
                }
            }

            handleRuntimeError(error)
            appendEntry(
                .actionCard(
                    ActionCard(
                        threadID: threadID,
                        method: "turn/start/error",
                        title: "Turn failed to start",
                        detail: error.localizedDescription
                    )
                ),
                to: threadID
            )
            throw error
        }
    }

    func startRuntimeSession() async {
        guard runtime != nil else {
            runtimeStatus = .error
            runtimeIssue = .recoverable("Runtime is unavailable.")
            return
        }

        await startRuntimeEventLoopIfNeeded()
        cancelAutomaticRuntimeRecovery()

        runtimeStatus = .starting
        do {
            try await connectRuntime(restarting: false)
            appendLog(.info, "Runtime connected")
        } catch {
            handleRuntimeError(error)
        }
    }

    func restartRuntimeSession() async {
        guard runtime != nil else { return }
        cancelAutomaticRuntimeRecovery()

        runtimeStatus = .starting
        runtimeIssue = nil

        do {
            try await connectRuntime(restarting: true)
            appendLog(.info, "Runtime restarted")
        } catch {
            handleRuntimeError(error)
        }
    }

    private func startRuntimeEventLoopIfNeeded() async {
        guard runtimeEventTask == nil,
              let runtime
        else {
            return
        }

        let stream = await runtime.events()
        runtimeEventTask = Task { [weak self] in
            guard let self else { return }

            for await event in stream {
                handleRuntimeEvent(event)
            }
        }
    }

    private func connectRuntime(restarting: Bool) async throws {
        guard let runtime else {
            throw CodexRuntimeError.processNotRunning
        }

        if restarting {
            try await runtime.restart()
        } else {
            try await runtime.start()
        }

        runtimeStatus = .connected
        runtimeIssue = nil
        runtimeSetupMessage = nil
        runtimeCapabilities = await runtime.capabilities()
        reconcileStaleApprovalState(
            reason: restarting ? "the runtime restarted" : "the runtime reconnected"
        )
        clearActiveTurnState()
        resetRuntimeThreadCaches()
        runtimeRepairSuggestedThreadIDs.removeAll()
        try await refreshAccountState(refreshToken: true)
        try await restorePersistedAPIKeyIfNeeded()
        await refreshRuntimeModelCatalog()
        refreshConversationState()
        requestAutoDrain(reason: "runtime connected")
    }

    private func cancelAutomaticRuntimeRecovery() {
        runtimeAutoRecoveryTask?.cancel()
        runtimeAutoRecoveryTask = nil
    }

    private func scheduleAutomaticRuntimeRecovery(afterTerminationDetail detail: String) {
        guard runtime != nil else { return }
        guard runtimeAutoRecoveryTask == nil else { return }

        let backoffSeconds: [UInt64] = [1, 2, 4, 8]
        runtimeAutoRecoveryTask = Task {
            defer { runtimeAutoRecoveryTask = nil }

            for (index, delay) in backoffSeconds.enumerated() {
                if Task.isCancelled {
                    return
                }

                let attempt = index + 1
                runtimeStatus = .starting
                runtimeIssue = .recoverable(
                    "Runtime exited unexpectedly. Attempting automatic restart (\(attempt)/\(backoffSeconds.count))…"
                )
                appendLog(.warning, "Auto-restart scheduled (\(attempt)/\(backoffSeconds.count)) after \(delay)s: \(detail)")

                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                if Task.isCancelled {
                    return
                }

                do {
                    try await connectRuntime(restarting: true)
                    appendLog(.info, "Automatic runtime recovery succeeded on attempt \(attempt)")
                    return
                } catch {
                    runtimeStatus = .error
                    runtimeIssue = .recoverable(error.localizedDescription)
                    appendLog(.error, "Automatic runtime recovery attempt \(attempt) failed: \(error.localizedDescription)")
                }
            }

            runtimeIssue = .recoverable(
                "Runtime stopped and automatic recovery failed. Use Restart Runtime to retry."
            )
        }
    }

    private func ensureRuntimeThreadID(
        for localThreadID: UUID,
        projectPath: String,
        safetyConfiguration: RuntimeSafetyConfiguration
    ) async throws -> String {
        if let cached = runtimeThreadIDByLocalThreadID[localThreadID] {
            return cached
        }

        if let persisted = try await runtimeThreadMappingRepository?.getRuntimeThreadID(localThreadID: localThreadID),
           !persisted.isEmpty
        {
            runtimeThreadIDByLocalThreadID[localThreadID] = persisted
            localThreadIDByRuntimeThreadID[persisted] = localThreadID
            appendLog(.debug, "Loaded persisted runtime thread mapping for local thread \(localThreadID.uuidString)")
            return persisted
        }

        return try await createAndPersistRuntimeThreadID(
            for: localThreadID,
            projectPath: projectPath,
            safetyConfiguration: safetyConfiguration
        )
    }

    private func createAndPersistRuntimeThreadID(
        for localThreadID: UUID,
        projectPath: String,
        safetyConfiguration: RuntimeSafetyConfiguration
    ) async throws -> String {
        guard let runtime else {
            throw CodexRuntimeError.processNotRunning
        }

        let runtimeThreadID = try await runtime.startThread(
            cwd: projectPath,
            safetyConfiguration: safetyConfiguration
        )
        try await runtimeThreadMappingRepository?.setRuntimeThreadID(
            localThreadID: localThreadID,
            runtimeThreadID: runtimeThreadID
        )
        runtimeThreadIDByLocalThreadID[localThreadID] = runtimeThreadID
        localThreadIDByRuntimeThreadID[runtimeThreadID] = localThreadID

        appendLog(.info, "Mapped local thread \(localThreadID.uuidString) to runtime thread \(runtimeThreadID)")
        return runtimeThreadID
    }

    private func invalidateRuntimeThreadID(for localThreadID: UUID) {
        guard let staleRuntimeThreadID = runtimeThreadIDByLocalThreadID.removeValue(forKey: localThreadID) else {
            return
        }
        localThreadIDByRuntimeThreadID.removeValue(forKey: staleRuntimeThreadID)
        appendLog(.debug, "Invalidated stale runtime thread mapping \(staleRuntimeThreadID)")
    }

    private func shouldRecreateRuntimeThread(after error: Error) -> Bool {
        let detail: String
        if let runtimeError = error as? CodexRuntimeError {
            switch runtimeError {
            case let .rpcError(_, message):
                detail = message
            case let .invalidResponse(message):
                detail = message
            default:
                return false
            }
        } else {
            detail = error.localizedDescription
        }

        let lowered = detail.lowercased()
        guard lowered.contains("thread") else {
            return false
        }

        let staleIndicators = [
            "unknown",
            "not found",
            "does not exist",
            "missing",
            "invalid",
        ]
        return staleIndicators.contains { lowered.contains($0) }
    }

    private func startTurnWithRuntimeFallback(
        runtime: CodexRuntime,
        threadID: String,
        text: String,
        safetyConfiguration: RuntimeSafetyConfiguration,
        skillInputs: [RuntimeSkillInput],
        inputItems: [RuntimeInputItem],
        turnOptions: RuntimeTurnOptions
    ) async throws -> String {
        do {
            return try await runtime.startTurn(
                threadID: threadID,
                text: text,
                safetyConfiguration: safetyConfiguration,
                skillInputs: skillInputs,
                inputItems: inputItems,
                turnOptions: turnOptions
            )
        } catch {
            guard shouldRetryWithoutTurnOptions(error) else {
                throw error
            }

            followUpStatusMessage = "Runtime rejected model/reasoning options. Retried with compatibility mode."
            appendLog(.warning, "Retrying turn/start without model/reasoning due to runtime compatibility.")
            return try await runtime.startTurn(
                threadID: threadID,
                text: text,
                safetyConfiguration: safetyConfiguration,
                skillInputs: skillInputs,
                inputItems: inputItems,
                turnOptions: nil
            )
        }
    }

    func shouldRetryWithoutTurnOptions(_ error: Error) -> Bool {
        let detail: String
        if let runtimeError = error as? CodexRuntimeError {
            switch runtimeError {
            case let .rpcError(_, message):
                detail = message
            case let .invalidResponse(message):
                detail = message
            default:
                return false
            }
        } else {
            detail = error.localizedDescription
        }

        let lowered = detail.lowercased()
        let indicatesUnsupported = lowered.contains("unknown")
            || lowered.contains("invalid")
            || lowered.contains("unsupported value")
            || lowered.contains("unsupported")
        let referencesTurnOptions = lowered.contains("model")
            || lowered.contains("reasoning")
            || lowered.contains("reasoningeffort")
            || lowered.contains("reasoning_effort")
            || lowered.contains("reasoning.effort")
            || lowered.contains("effort")
        return indicatesUnsupported && referencesTurnOptions
    }

    private func captureModSnapshot(
        projectPath: String,
        threadID: UUID,
        startedAt: Date,
        fileManager: FileManager = .default
    ) throws -> ModEditSafety.Snapshot {
        let snapshotsRootURL = try Self.modSnapshotsRootURL(fileManager: fileManager)
        let globalRootPath = try Self.globalModsRootPath(fileManager: fileManager)
        let projectRootPath = Self.projectModsRootPath(projectPath: projectPath)

        let snapshot = try ModEditSafety.captureSnapshot(
            snapshotsRootURL: snapshotsRootURL,
            globalRootPath: globalRootPath,
            projectRootPath: projectRootPath,
            threadID: threadID,
            startedAt: startedAt,
            fileManager: fileManager
        )
        appendLog(.debug, "Captured mod snapshot at \(snapshot.rootURL.lastPathComponent)")
        return snapshot
    }

    private static func modSnapshotsRootURL(fileManager: FileManager = .default) throws -> URL {
        let storagePaths = CodexChatStoragePaths.current(fileManager: fileManager)
        let root = storagePaths.modSnapshotsURL
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func clearActiveTurnState() {
        if let context = activeTurnContext {
            assistantMessageIDsByItemID[context.localThreadID] = [:]
            localThreadIDByCommandItemID = localThreadIDByCommandItemID.filter { $0.value != context.localThreadID }
            activeTurnContext = nil
        }

        isTurnInProgress = false

        // If a mod review is pending, keep the snapshot so the user can still revert.
        if pendingModReview == nil {
            discardModSnapshotIfPresent()
        }
    }

    private func resetRuntimeThreadCaches() {
        runtimeThreadIDByLocalThreadID.removeAll()
        localThreadIDByRuntimeThreadID.removeAll()
        localThreadIDByCommandItemID.removeAll()
        clearPendingRuntimeRepairSuggestions()
    }

    func handleRuntimeTermination(detail: String) {
        runtimeStatus = .error
        runtimeCapabilities = .none
        cancelVoiceCapture()
        reconcileStaleApprovalState(reason: "the runtime stopped unexpectedly")
        runtimeIssue = .recoverable(detail)
        clearActiveTurnState()
        resetRuntimeThreadCaches()
        appendLog(.error, detail)
        scheduleAutomaticRuntimeRecovery(afterTerminationDetail: detail)
    }

    func handleRuntimeError(_ error: Error) {
        runtimeStatus = .error
        runtimeCapabilities = .none
        cancelVoiceCapture()
        reconcileStaleApprovalState(reason: "runtime communication failed")
        clearActiveTurnState()
        resetRuntimeThreadCaches()

        if let runtimeError = error as? CodexRuntimeError {
            switch runtimeError {
            case .binaryNotFound:
                runtimeIssue = .installCodex
            case let .handshakeFailed(detail):
                runtimeIssue = .recoverable(detail)
            default:
                runtimeIssue = .recoverable(protocolCompatibilityGuidance(for: runtimeError) ?? runtimeError.localizedDescription)
            }
            appendLog(.error, runtimeError.localizedDescription)
            return
        }

        runtimeIssue = .recoverable(error.localizedDescription)
        appendLog(.error, error.localizedDescription)
    }

    private func restorePersistedAPIKeyIfNeeded() async throws {
        guard let runtime else { return }

        // If runtime already has a valid authenticated account (e.g., ChatGPT managed auth),
        // do not override it with an API key from Keychain.
        if accountState.account != nil || !accountState.requiresOpenAIAuth {
            return
        }

        guard let apiKey = try keychainStore.readSecret(account: APIKeychainStore.runtimeAPIKeyAccount),
              !apiKey.isEmpty
        else {
            return
        }

        appendLog(.info, "Restoring API key session from Keychain")
        try await runtime.startAPIKeyLogin(apiKey: apiKey)
        try await refreshAccountState(refreshToken: true)
        accountStatusMessage = "Restored API key session from Keychain."
    }

    func refreshRuntimeModelCatalog() async {
        guard let runtime else {
            return
        }

        do {
            let models = try await runtime.listAllModels()
            runtimeModelCatalog = models
            applyDerivedRuntimeDefaultsFromConfig()
            appendLog(.info, "Loaded \(models.count) models from runtime")
        } catch {
            appendLog(.warning, "Failed to load runtime model catalog: \(error.localizedDescription)")
            if runtimeModelCatalog.isEmpty {
                applyDerivedRuntimeDefaultsFromConfig()
            }
        }
    }

    private func reconcileStaleApprovalState(reason: String) {
        let pendingRequest = activeApprovalRequest ?? approvalStateMachine.activeRequest
        let hadPendingApprovals = approvalStateMachine.hasPendingApprovals
            || activeApprovalRequest != nil
            || isApprovalDecisionInProgress

        approvalStateMachine.clear()
        activeApprovalRequest = nil
        isApprovalDecisionInProgress = false

        guard hadPendingApprovals else {
            return
        }

        let message = "Approval request was reset because \(reason). Re-run the action to request approval again."
        approvalStatusMessage = message
        appendLog(.warning, message)

        guard let localThreadID = localThreadIDForPendingApproval(pendingRequest) else {
            return
        }

        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: localThreadID,
                    method: "approval/reset",
                    title: "Approval reset",
                    detail: message
                )
            ),
            to: localThreadID
        )
    }

    private func localThreadIDForPendingApproval(_ request: RuntimeApprovalRequest?) -> UUID? {
        if let itemID = request?.itemID,
           let mappedThreadID = localThreadIDByCommandItemID[itemID]
        {
            return mappedThreadID
        }

        if let runtimeThreadID = request?.threadID {
            if let mappedThreadID = localThreadIDByRuntimeThreadID[runtimeThreadID] {
                return mappedThreadID
            }

            if let activeTurnContext,
               activeTurnContext.runtimeThreadID == runtimeThreadID
            {
                return activeTurnContext.localThreadID
            }
        }

        return activeTurnContext?.localThreadID
    }

    private func protocolCompatibilityGuidance(for error: CodexRuntimeError) -> String? {
        guard case let .rpcError(code, message) = error else {
            return nil
        }

        let lowered = message.lowercased()
        let schemaMismatchCode = code == -32600 || code == -32601 || code == -32602
        let schemaMismatchMessage = lowered.contains("unknown variant")
            || lowered.contains("unknown field")
            || lowered.contains("missing field")
            || lowered.contains("invalid request")
            || lowered.contains("unsupported value")
            || lowered.contains("expectedturnid")
            || lowered.contains("approvalpolicy")
            || lowered.contains("reasoning.effort")
            || lowered.contains("reasoningeffort")
            || lowered.contains("effort")

        guard schemaMismatchCode, schemaMismatchMessage else {
            return nil
        }

        return "Runtime protocol mismatch detected. Update Codex CLI and restart the runtime."
    }
}
