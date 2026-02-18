import CodexChatCore
import CodexKit
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

    func handleRuntimeTermination(detail: String) {
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
