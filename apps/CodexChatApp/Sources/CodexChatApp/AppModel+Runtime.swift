import CodexChatCore
import CodexKit
import CodexMemory
import Foundation

extension AppModel {
    func sendMessage() {
        guard let selectedThreadID,
              let selectedProjectID,
              let project = selectedProject,
              let runtime,
              canSendMessages
        else {
            return
        }

        let trimmedText = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        composerText = ""
        isTurnInProgress = true
        appendEntry(.message(ChatMessage(threadId: selectedThreadID, role: .user, text: trimmedText)), to: selectedThreadID)
        let safetyConfiguration = runtimeSafetyConfiguration(for: project)
        let selectedSkillInput = selectedSkillForComposer.map {
            RuntimeSkillInput(name: $0.skill.name, path: $0.skill.skillPath)
        }

        Task {
            do {
                let runtimeThreadID = try await ensureRuntimeThreadID(
                    for: selectedThreadID,
                    projectPath: project.path,
                    safetyConfiguration: safetyConfiguration
                )
                let startedAt = Date()
                activeTurnContext = ActiveTurnContext(
                    localThreadID: selectedThreadID,
                    projectID: selectedProjectID,
                    projectPath: project.path,
                    runtimeThreadID: runtimeThreadID,
                    userText: trimmedText,
                    assistantText: "",
                    actions: [],
                    startedAt: startedAt
                )

                activeModSnapshot = {
                    do {
                        return try captureModSnapshot(
                            projectPath: project.path,
                            threadID: selectedThreadID,
                            startedAt: startedAt
                        )
                    } catch {
                        appendLog(.warning, "Failed to capture mod snapshot: \(error.localizedDescription)")
                        return nil
                    }
                }()

                let turnID = try await runtime.startTurn(
                    threadID: runtimeThreadID,
                    text: trimmedText,
                    safetyConfiguration: safetyConfiguration,
                    skillInputs: selectedSkillInput.map { [$0] } ?? []
                )
                appendLog(.info, "Started turn \(turnID) for local thread \(selectedThreadID.uuidString)")
            } catch {
                handleRuntimeError(error)
                appendEntry(
                    .actionCard(
                        ActionCard(
                            threadID: selectedThreadID,
                            method: "turn/start/error",
                            title: "Turn failed to start",
                            detail: error.localizedDescription
                        )
                    ),
                    to: selectedThreadID
                )
            }
        }
    }

    func startRuntimeSession() async {
        guard let runtime else {
            runtimeStatus = .error
            runtimeIssue = .recoverable("Runtime is unavailable.")
            return
        }

        await startRuntimeEventLoopIfNeeded()

        runtimeStatus = .starting
        do {
            try await runtime.start()
            runtimeStatus = .connected
            runtimeIssue = nil
            approvalStateMachine.clear()
            activeApprovalRequest = nil
            clearActiveTurnState()
            resetRuntimeThreadCaches()
            appendLog(.info, "Runtime connected")
            try await refreshAccountState()
        } catch {
            handleRuntimeError(error)
        }
    }

    func restartRuntimeSession() async {
        guard let runtime else { return }

        runtimeStatus = .starting
        runtimeIssue = nil

        do {
            try await runtime.restart()
            runtimeStatus = .connected
            runtimeIssue = nil
            approvalStateMachine.clear()
            activeApprovalRequest = nil
            clearActiveTurnState()
            resetRuntimeThreadCaches()
            appendLog(.info, "Runtime restarted")
            try await refreshAccountState()
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

    private func handleRuntimeEvent(_ event: CodexRuntimeEvent) {
        switch event {
        case let .threadStarted(threadID):
            appendLog(.debug, "Runtime thread started: \(threadID)")

        case let .turnStarted(turnID):
            if let context = activeTurnContext {
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
            }

        case let .assistantMessageDelta(itemID, delta):
            guard let context = activeTurnContext else {
                appendLog(.debug, "Dropped delta with no active turn")
                return
            }

            appendAssistantDelta(delta, itemID: itemID, to: context.localThreadID)
            var updatedContext = context
            updatedContext.assistantText += delta
            activeTurnContext = updatedContext

        case let .commandOutputDelta(output):
            handleCommandOutputDelta(output)

        case let .fileChangesUpdated(update):
            handleFileChangesUpdate(update)

        case let .approvalRequested(request):
            handleApprovalRequest(request)

        case let .action(action):
            handleRuntimeAction(action)

        case let .turnCompleted(completion):
            isTurnInProgress = false
            if let context = activeTurnContext {
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

                assistantMessageIDsByItemID[context.localThreadID] = [:]
                localThreadIDByCommandItemID = localThreadIDByCommandItemID.filter { $0.value != context.localThreadID }
                processModChangesIfNeeded(context: context)
                activeTurnContext = nil

                Task {
                    await persistCompletedTurn(context: context)
                }
            } else {
                appendLog(.debug, "Turn completed without active context: \(completion.status)")
            }

        case let .accountUpdated(authMode):
            appendLog(.info, "Account mode updated: \(authMode.rawValue)")
            Task {
                try? await refreshAccountState()
            }

        case let .accountLoginCompleted(completion):
            if completion.success {
                accountStatusMessage = "Login completed."
                appendLog(.info, "Login completed")
            } else {
                let detail = completion.error ?? "Unknown error"
                accountStatusMessage = "Login failed: \(detail)"
                appendLog(.error, "Login failed: \(detail)")
            }
            Task {
                try? await refreshAccountState()
            }
        }
    }

    private func handleRuntimeAction(_ action: RuntimeAction) {
        if action.method == "runtime/stderr" {
            appendLog(.warning, action.detail)
        }

        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: action.threadID,
            itemID: action.itemID
        ) ?? activeTurnContext?.localThreadID

        if action.method == "runtime/terminated" {
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
            detail: action.detail
        )
        appendEntry(.actionCard(card), to: localThreadID)

        if var context = activeTurnContext,
           context.localThreadID == localThreadID
        {
            context.actions.append(card)
            activeTurnContext = context
        }
    }

    private func handleCommandOutputDelta(_ output: RuntimeCommandOutputDelta) {
        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: output.threadID,
            itemID: output.itemID
        ) ?? activeTurnContext?.localThreadID

        guard let localThreadID else {
            appendLog(.debug, "Command output delta without thread mapping")
            return
        }

        appendThreadLog(
            level: .info,
            text: output.delta,
            to: localThreadID
        )
    }

    private func handleFileChangesUpdate(_ update: RuntimeFileChangeUpdate) {
        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: update.threadID,
            itemID: update.itemID
        ) ?? activeTurnContext?.localThreadID

        guard let localThreadID else {
            appendLog(.debug, "File changes update without thread mapping")
            return
        }

        reviewChangesByThreadID[localThreadID] = update.changes
    }

    private func handleApprovalRequest(_ request: RuntimeApprovalRequest) {
        approvalStateMachine.enqueue(request)
        activeApprovalRequest = approvalStateMachine.activeRequest
        approvalStatusMessage = nil

        let localThreadID = resolveLocalThreadID(
            runtimeThreadID: request.threadID,
            itemID: request.itemID
        ) ?? activeTurnContext?.localThreadID

        guard let localThreadID else {
            appendLog(.warning, "Approval request arrived without local thread mapping")
            return
        }

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
    }

    private func resolveLocalThreadID(runtimeThreadID: String?, itemID: String?) -> UUID? {
        if let itemID, let threadID = localThreadIDByCommandItemID[itemID] {
            return threadID
        }

        if let runtimeThreadID {
            if let mapped = localThreadIDByRuntimeThreadID[runtimeThreadID] {
                return mapped
            }
            if let activeTurnContext, activeTurnContext.runtimeThreadID == runtimeThreadID {
                return activeTurnContext.localThreadID
            }
        }

        return nil
    }

    private func ensureRuntimeThreadID(
        for localThreadID: UUID,
        projectPath: String,
        safetyConfiguration: RuntimeSafetyConfiguration
    ) async throws -> String {
        if let cached = runtimeThreadIDByLocalThreadID[localThreadID] {
            return cached
        }

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

    private func persistCompletedTurn(context: ActiveTurnContext) async {
        let assistantText = context.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)

        let summary = ArchivedTurnSummary(
            timestamp: context.startedAt,
            userText: context.userText,
            assistantText: assistantText,
            actions: context.actions
        )

        do {
            let archiveURL = try ChatArchiveStore.appendTurn(
                projectPath: context.projectPath,
                threadID: context.localThreadID,
                turn: summary
            )
            projectStatusMessage = "Archived chat turn to \(archiveURL.lastPathComponent)."

            try await chatSearchRepository?.indexMessageExcerpt(
                threadID: context.localThreadID,
                projectID: context.projectID,
                text: context.userText
            )

            if !assistantText.isEmpty {
                try await chatSearchRepository?.indexMessageExcerpt(
                    threadID: context.localThreadID,
                    projectID: context.projectID,
                    text: assistantText
                )
            }
        } catch {
            appendLog(.error, "Failed to archive turn: \(error.localizedDescription)")
        }

        await appendMemorySummaryIfEnabled(context: context, assistantText: assistantText)
    }

    private func appendMemorySummaryIfEnabled(context: ActiveTurnContext, assistantText: String) async {
        guard let projectRepository else { return }

        do {
            let project = try await projectRepository.getProject(id: context.projectID) ?? selectedProject
            guard let project, project.memoryWriteMode != .off else {
                return
            }

            let store = ProjectMemoryStore(projectPath: context.projectPath)
            try await store.ensureStructure()
            let markdown = MemoryAutoSummary.markdown(
                timestamp: context.startedAt,
                threadID: context.localThreadID,
                userText: context.userText,
                assistantText: assistantText,
                actions: context.actions,
                mode: project.memoryWriteMode
            )

            try await store.appendToSummaryLog(markdown: markdown)
            appendLog(.info, "Appended memory summary for thread \(context.localThreadID.uuidString)")
        } catch {
            appendLog(.error, "Failed to append memory summary: \(error.localizedDescription)")
        }
    }

    private func processModChangesIfNeeded(context: ActiveTurnContext) {
        guard pendingModReview == nil else { return }

        let changes = reviewChangesByThreadID[context.localThreadID] ?? []
        guard !changes.isEmpty else {
            discardModSnapshotIfPresent()
            return
        }

        let snapshot = activeModSnapshot
        let projectRootPath = snapshot?.projectRootPath ?? Self.projectModsRootPath(projectPath: context.projectPath)
        let globalRootPath = snapshot?.globalRootPath ?? (try? Self.globalModsRootPath())

        let modChanges = ModEditSafety.filterModChanges(
            changes: changes,
            projectPath: context.projectPath,
            globalRootPath: globalRootPath,
            projectRootPath: projectRootPath
        )

        guard !modChanges.isEmpty else {
            discardModSnapshotIfPresent()
            return
        }

        pendingModReview = PendingModReview(
            id: UUID(),
            threadID: context.localThreadID,
            changes: modChanges,
            reason: "Codex proposed edits to mod files. Review is required before continuing.",
            canRevert: snapshot != nil
        )

        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: context.localThreadID,
                    method: "mods/reviewRequired",
                    title: "Mod changes require approval",
                    detail: "Review and accept or revert \(modChanges.count) mod-related change(s)."
                )
            ),
            to: context.localThreadID
        )
    }

    private func discardModSnapshotIfPresent() {
        guard let snapshot = activeModSnapshot else { return }
        ModEditSafety.discard(snapshot: snapshot)
        activeModSnapshot = nil
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
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base
            .appendingPathComponent("CodexChat", isDirectory: true)
            .appendingPathComponent("ModSnapshots", isDirectory: true)
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
    }

    private func handleRuntimeTermination(detail: String) {
        runtimeStatus = .error
        approvalStateMachine.clear()
        activeApprovalRequest = nil
        isApprovalDecisionInProgress = false
        runtimeIssue = .recoverable(detail)
        clearActiveTurnState()
        resetRuntimeThreadCaches()
        appendLog(.error, detail)
    }

    func handleRuntimeError(_ error: Error) {
        runtimeStatus = .error
        approvalStateMachine.clear()
        activeApprovalRequest = nil
        isApprovalDecisionInProgress = false
        clearActiveTurnState()
        resetRuntimeThreadCaches()

        if let runtimeError = error as? CodexRuntimeError {
            switch runtimeError {
            case .binaryNotFound:
                runtimeIssue = .installCodex
            case let .handshakeFailed(detail):
                runtimeIssue = .recoverable(detail)
            default:
                runtimeIssue = .recoverable(runtimeError.localizedDescription)
            }
            appendLog(.error, runtimeError.localizedDescription)
            return
        }

        runtimeIssue = .recoverable(error.localizedDescription)
        appendLog(.error, error.localizedDescription)
    }
}
