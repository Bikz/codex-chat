import AppKit
import CodexChatCore
import CodexKit
import CodexMemory
import CryptoKit
import Foundation

extension AppModel {
    func revealSelectedThreadArchiveInFinder() {
        guard let threadID = selectedThreadID,
              let project = selectedProject
        else {
            return
        }

        guard let archiveURL = ChatArchiveStore.latestArchiveURL(projectPath: project.path, threadID: threadID) else {
            projectStatusMessage = "No thread transcript file found for the selected thread yet."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
        projectStatusMessage = "Revealed \(archiveURL.lastPathComponent) in Finder."
    }

    func selectProject(_ projectID: UUID?) {
        let transitionGeneration = beginSelectionTransition()
        let task = Task { [weak self] in
            guard let self else { return }
            let span = await PerformanceTracer.shared.begin(
                name: "thread.selectProject",
                metadata: ["projectID": projectID?.uuidString ?? "nil"]
            )
            defer {
                Task {
                    await PerformanceTracer.shared.end(span)
                }
                finishSelectionTransition(transitionGeneration)
            }

            let previousProjectID = selectedProjectID
            selectedProjectID = projectID
            selectedThreadID = nil
            if draftChatProjectID != projectID {
                draftChatProjectID = nil
            }
            refreshConversationState()
            appendLog(.debug, "Selected project: \(projectID?.uuidString ?? "none")")

            do {
                try await persistSelection()
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                try await refreshThreads()
                if let selectedThreadID {
                    try await refreshFollowUpQueue(threadID: selectedThreadID)
                    await rehydrateThreadTranscript(threadID: selectedThreadID)
                }
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                refreshConversationStateIfSelectedThreadChanged(selectedThreadID)
                scheduleProjectSecondarySurfaceRefresh(
                    transitionGeneration: transitionGeneration,
                    targetProjectID: projectID,
                    projectContextChanged: previousProjectID != projectID,
                    reason: "selectProject"
                )
            } catch {
                threadsState = .failed(error.localizedDescription)
                appendLog(.error, "Select project failed: \(error.localizedDescription)")
            }
        }
        registerSelectionTransitionTask(task, generation: transitionGeneration)
    }

    func createThread() {
        guard let projectID = selectedProjectID else { return }
        beginDraftChat(in: projectID)
    }

    func createThread(in projectID: UUID) {
        beginDraftChat(in: projectID)
    }

    func createGeneralThread() {
        guard let generalProjectID = generalProject?.id else { return }
        beginDraftChat(in: generalProjectID)
    }

    func createGlobalNewChat() {
        createGeneralThread()
    }

    func refreshArchivedThreads() async throws {
        guard let threadRepository else {
            archivedThreadsState = .failed("Thread repository is unavailable.")
            return
        }
        archivedThreadsState = .loading
        let archived = try await threadRepository.listArchivedThreads()
        archivedThreadsState = .loaded(archived)
    }

    func togglePin(threadID: UUID) {
        Task {
            guard let threadRepository else { return }
            do {
                guard let thread = try await threadRepository.getThread(id: threadID) else {
                    return
                }
                guard thread.archivedAt == nil else {
                    return
                }
                _ = try await threadRepository.setThreadPinned(id: threadID, isPinned: !thread.isPinned)
                try await refreshThreadListsAfterMutation(projectID: thread.projectId)
            } catch {
                appendLog(.error, "Toggle thread pin failed: \(error.localizedDescription)")
            }
        }
    }

    func archiveThread(threadID: UUID) {
        Task {
            guard let threadRepository else { return }
            do {
                guard try await threadRepository.getThread(id: threadID) != nil else {
                    return
                }

                let archived = try await threadRepository.archiveThread(id: threadID, archivedAt: Date())
                try await archiveThreadMemoryInfluence(thread: archived)

                if selectedThreadID == threadID {
                    try await selectFallbackThreadAfterArchive(archivedThread: archived)
                }

                try await refreshThreadListsAfterMutation(projectID: archived.projectId)
                projectStatusMessage = "Archived chat \(archived.title)."
            } catch {
                appendLog(.error, "Archive thread failed: \(error.localizedDescription)")
            }
        }
    }

    func unarchiveThread(threadID: UUID) {
        Task {
            guard let threadRepository else { return }
            do {
                guard let thread = try await threadRepository.getThread(id: threadID) else {
                    return
                }

                let unarchived = try await threadRepository.unarchiveThread(id: threadID)
                try await restoreThreadMemoryInfluence(thread: unarchived)
                try await refreshThreadListsAfterMutation(projectID: thread.projectId)
                projectStatusMessage = "Unarchived chat \(unarchived.title)."
            } catch {
                appendLog(.error, "Unarchive thread failed: \(error.localizedDescription)")
            }
        }
    }

    func selectThread(_ threadID: UUID?) {
        selectedThreadID = threadID
        if threadID != nil {
            draftChatProjectID = nil
            detailDestination = .thread
        }
        refreshConversationState()
        appendLog(.debug, "Selected thread: \(threadID?.uuidString ?? "none")")

        let transitionGeneration = beginSelectionTransition()
        let task = Task { [weak self] in
            guard let self else { return }
            let span = await PerformanceTracer.shared.begin(
                name: "thread.selectThread",
                metadata: ["threadID": threadID?.uuidString ?? "nil"]
            )
            defer {
                Task {
                    await PerformanceTracer.shared.end(span)
                }
                finishSelectionTransition(transitionGeneration)
            }

            do {
                let didAlignProject = await alignSelectedProjectToSelectedThreadIfNeeded(threadID: threadID)
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                guard selectedThreadID == threadID else {
                    return
                }

                try await persistSelection()
                guard isCurrentSelectionTransition(transitionGeneration) else { return }

                if didAlignProject {
                    scheduleProjectSecondarySurfaceRefresh(
                        transitionGeneration: transitionGeneration,
                        targetProjectID: selectedProjectID,
                        projectContextChanged: true,
                        reason: "selectThread"
                    )
                }

                if let threadID {
                    try await refreshFollowUpQueue(threadID: threadID)
                    await rehydrateThreadTranscript(threadID: threadID)
                }
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                refreshConversationStateIfSelectedThreadChanged(threadID)
                requestAutoDrain(reason: "thread selection changed")
            } catch {
                conversationState = .failed(error.localizedDescription)
                appendLog(.error, "Select thread failed: \(error.localizedDescription)")
            }
        }
        registerSelectionTransitionTask(task, generation: transitionGeneration)
    }

    private func alignSelectedProjectToSelectedThreadIfNeeded(threadID: UUID?) async -> Bool {
        guard let threadID else {
            return false
        }

        guard let resolvedProjectID = await projectIDForSelectedThread(threadID: threadID) else {
            return false
        }

        guard selectedProjectID != resolvedProjectID else {
            return false
        }

        selectedProjectID = resolvedProjectID
        appendLog(.debug, "Aligned selected project to thread project: \(resolvedProjectID.uuidString)")
        return true
    }

    private func projectIDForSelectedThread(threadID: UUID) async -> UUID? {
        if let selected = (threads + generalThreads + archivedThreads).first(where: { $0.id == threadID }) {
            return selected.projectId
        }

        guard let threadRepository else {
            return nil
        }

        do {
            let thread = try await threadRepository.getThread(id: threadID)
            return thread?.projectId
        } catch {
            appendLog(.warning, "Failed to resolve project for selected thread \(threadID.uuidString): \(error.localizedDescription)")
            return nil
        }
    }

    private func selectFallbackThreadAfterArchive(archivedThread: ThreadRecord) async throws {
        guard let threadRepository else { return }
        let activeThreads = try await threadRepository.listThreads(projectID: archivedThread.projectId, scope: .active)
        selectedThreadID = activeThreads.first?.id
        if selectedProjectID != archivedThread.projectId {
            selectedProjectID = archivedThread.projectId
        }
        try await persistSelection()
        if let selectedThreadID {
            try await refreshFollowUpQueue(threadID: selectedThreadID)
            await rehydrateThreadTranscript(threadID: selectedThreadID)
        }
        refreshConversationState()
    }

    private func refreshThreadListsAfterMutation(projectID: UUID) async throws {
        if selectedProjectID == projectID {
            try await refreshThreads()
        }
        if generalProject?.id == projectID {
            try await refreshGeneralThreads(generalProjectID: projectID)
        }
        try await refreshArchivedThreads()
    }

    private func archiveThreadMemoryInfluence(thread: ThreadRecord) async throws {
        guard let project = projects.first(where: { $0.id == thread.projectId }) else {
            return
        }
        let store = ProjectMemoryStore(projectPath: project.path)
        _ = try await store.archiveSummaryEntries(for: thread.id)
    }

    private func restoreThreadMemoryInfluence(thread: ThreadRecord) async throws {
        guard let project = projects.first(where: { $0.id == thread.projectId }) else {
            return
        }
        let store = ProjectMemoryStore(projectPath: project.path)
        _ = try await store.restoreArchivedSummaryEntries(for: thread.id)
    }

    func beginDraftChat(in projectID: UUID) {
        let previousProjectID = selectedProjectID
        selectedProjectID = projectID
        selectedThreadID = nil
        draftChatProjectID = projectID
        detailDestination = .thread
        refreshConversationState()
        appendLog(.info, "Started draft chat for project \(projectID.uuidString)")

        let transitionGeneration = beginSelectionTransition()
        let task = Task { [weak self] in
            guard let self else { return }
            let span = await PerformanceTracer.shared.begin(
                name: "thread.beginDraftChat",
                metadata: ["projectID": projectID.uuidString]
            )
            defer {
                Task {
                    await PerformanceTracer.shared.end(span)
                }
                finishSelectionTransition(transitionGeneration)
            }

            do {
                if generalProject?.id == projectID {
                    try await refreshGeneralThreads(generalProjectID: projectID)
                } else {
                    try await refreshThreads()
                }
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                try await persistSelection()
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                refreshConversationStateIfSelectedThreadChanged(selectedThreadID)
                scheduleProjectSecondarySurfaceRefresh(
                    transitionGeneration: transitionGeneration,
                    targetProjectID: projectID,
                    projectContextChanged: previousProjectID != projectID,
                    reason: "beginDraftChat"
                )
            } catch {
                appendLog(.error, "Start draft chat failed: \(error.localizedDescription)")
            }
        }
        registerSelectionTransitionTask(task, generation: transitionGeneration)
    }

    func materializeDraftThreadIfNeeded() async throws -> UUID {
        let span = await PerformanceTracer.shared.begin(name: "thread.materializeDraftThread")
        defer {
            Task {
                await PerformanceTracer.shared.end(span)
            }
        }

        if let selectedThreadID {
            return selectedThreadID
        }

        guard let selectedProjectID,
              draftChatProjectID == selectedProjectID,
              let threadRepository
        else {
            throw CodexRuntimeError.invalidResponse("No draft chat is active.")
        }

        let title = "New chat"
        let thread = try await threadRepository.createThread(projectID: selectedProjectID, title: title)
        pendingFirstTurnTitleThreadIDs.insert(thread.id)

        try await chatSearchRepository?.indexThreadTitle(
            threadID: thread.id,
            projectID: selectedProjectID,
            title: title
        )

        if generalProject?.id == selectedProjectID {
            try await refreshGeneralThreads(generalProjectID: selectedProjectID)
        } else {
            try await refreshThreads()
        }
        try await refreshArchivedThreads()
        selectedThreadID = thread.id
        draftChatProjectID = nil
        detailDestination = .thread
        try await persistSelection()
        try await refreshFollowUpQueue(threadID: thread.id)
        refreshConversationState()
        appendLog(.info, "Created thread from draft chat \(thread.id.uuidString)")
        return thread.id
    }

    func rehydrateThreadTranscript(threadID: UUID, limit: Int = 50) async {
        let span = await PerformanceTracer.shared.begin(
            name: "thread.rehydrateTranscript",
            metadata: ["threadID": threadID.uuidString, "limit": "\(limit)"]
        )
        defer {
            Task {
                await PerformanceTracer.shared.end(span)
            }
        }

        do {
            guard let projectPath = try await projectPathForThread(threadID: threadID) else {
                return
            }
            let turns = try await Task.detached(priority: .userInitiated) {
                try ChatArchiveStore.loadRecentTurns(
                    projectPath: projectPath,
                    threadID: threadID,
                    limit: limit
                )
            }.value
            let entries = await Task.detached(priority: .userInitiated) {
                Self.transcriptEntries(from: turns, threadID: threadID)
            }.value
            transcriptStore[threadID] = entries
            bumpTranscriptRevision(for: threadID)
        } catch {
            appendLog(
                .warning,
                "Failed to rehydrate transcript for thread \(threadID.uuidString): \(error.localizedDescription)"
            )
        }
    }

    private func projectPathForThread(threadID: UUID) async throws -> String? {
        if let selectedProject,
           selectedThreadID == threadID
        {
            return selectedProject.path
        }

        guard let thread = try await threadRepository?.getThread(id: threadID),
              let project = try await projectRepository?.getProject(id: thread.projectId)
        else {
            return nil
        }
        return project.path
    }

    private nonisolated static func transcriptEntries(
        from turns: [ArchivedTurnSummary],
        threadID: UUID
    ) -> [TranscriptEntry] {
        var entries: [TranscriptEntry] = []
        entries.reserveCapacity(turns.count * 3)

        for turn in turns {
            let userMessage = ChatMessage(
                id: deterministicMessageID(
                    threadID: threadID,
                    turnID: turn.turnID,
                    role: .user,
                    ordinal: 0
                ),
                threadId: threadID,
                role: .user,
                text: turn.userText,
                createdAt: turn.timestamp
            )
            entries.append(.message(userMessage))

            let assistantText = turn.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !assistantText.isEmpty {
                let assistantMessage = ChatMessage(
                    id: deterministicMessageID(
                        threadID: threadID,
                        turnID: turn.turnID,
                        role: .assistant,
                        ordinal: 0
                    ),
                    threadId: threadID,
                    role: .assistant,
                    text: assistantText,
                    createdAt: turn.timestamp
                )
                entries.append(.message(assistantMessage))
            }

            for action in turn.actions {
                let normalizedAction = ActionCard(
                    id: action.id,
                    threadID: threadID,
                    method: action.method,
                    title: action.title,
                    detail: action.detail,
                    createdAt: action.createdAt
                )
                entries.append(.actionCard(normalizedAction))
            }
        }

        return entries
    }

    private nonisolated static func deterministicMessageID(
        threadID: UUID,
        turnID: UUID,
        role: ChatMessageRole,
        ordinal: Int
    ) -> UUID {
        let payload = "\(threadID.uuidString)|\(turnID.uuidString)|\(role.rawValue)|\(ordinal)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        let bytes = Array(digest.prefix(16))
        guard bytes.count == 16 else {
            return turnID
        }

        let versionedByte6 = (bytes[6] & 0x0F) | 0x40
        let variantByte8 = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], versionedByte6, bytes[7],
            variantByte8, bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
