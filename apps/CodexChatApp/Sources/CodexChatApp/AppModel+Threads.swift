import AppKit
import CodexChatCore
import CodexKit
import CodexMemory
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
        Task {
            selectedProjectID = projectID
            selectedThreadID = nil
            if draftChatProjectID != projectID {
                draftChatProjectID = nil
            }
            appendLog(.debug, "Selected project: \(projectID?.uuidString ?? "none")")

            do {
                try await persistSelection()
                try await refreshThreads()
                try await refreshSkills()
                refreshModsSurface()
                if let selectedThreadID {
                    try await refreshFollowUpQueue(threadID: selectedThreadID)
                    await rehydrateThreadTranscript(threadID: selectedThreadID)
                }
                refreshConversationState()
            } catch {
                threadsState = .failed(error.localizedDescription)
                appendLog(.error, "Select project failed: \(error.localizedDescription)")
            }
        }
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
        appendLog(.debug, "Selected thread: \(threadID?.uuidString ?? "none")")

        Task {
            do {
                let didAlignProject = await alignSelectedProjectToSelectedThreadIfNeeded(threadID: threadID)
                guard selectedThreadID == threadID else {
                    return
                }

                try await persistSelection()

                if didAlignProject {
                    do {
                        try await refreshSkills()
                        refreshModsSurface()
                    } catch {
                        appendLog(
                            .warning,
                            "Failed to refresh project-scoped surfaces after thread selection: \(error.localizedDescription)"
                        )
                    }
                }

                if let threadID {
                    try await refreshFollowUpQueue(threadID: threadID)
                    await rehydrateThreadTranscript(threadID: threadID)
                }
                refreshConversationState()
                requestAutoDrain(reason: "thread selection changed")
            } catch {
                conversationState = .failed(error.localizedDescription)
                appendLog(.error, "Select thread failed: \(error.localizedDescription)")
            }
        }
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
        selectedProjectID = projectID
        selectedThreadID = nil
        draftChatProjectID = projectID
        detailDestination = .thread
        appendLog(.info, "Started draft chat for project \(projectID.uuidString)")

        Task {
            do {
                if generalProject?.id == projectID {
                    try await refreshGeneralThreads(generalProjectID: projectID)
                } else {
                    try await refreshThreads()
                }
                try await refreshSkills()
                refreshModsSurface()
                try await persistSelection()
                refreshConversationState()
            } catch {
                appendLog(.error, "Start draft chat failed: \(error.localizedDescription)")
            }
        }
    }

    func materializeDraftThreadIfNeeded() async throws -> UUID {
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
        do {
            guard let projectPath = try await projectPathForThread(threadID: threadID) else {
                return
            }
            let turns = try ChatArchiveStore.loadRecentTurns(
                projectPath: projectPath,
                threadID: threadID,
                limit: limit
            )
            transcriptStore[threadID] = Self.transcriptEntries(from: turns, threadID: threadID)
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

    private static func transcriptEntries(
        from turns: [ArchivedTurnSummary],
        threadID: UUID
    ) -> [TranscriptEntry] {
        let ordered = turns.sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            return $0.turnID.uuidString < $1.turnID.uuidString
        }

        var entries: [TranscriptEntry] = []
        entries.reserveCapacity(ordered.count * 3)

        for turn in ordered {
            let userMessage = ChatMessage(
                id: UUID(),
                threadId: threadID,
                role: .user,
                text: turn.userText,
                createdAt: turn.timestamp
            )
            entries.append(.message(userMessage))

            let assistantText = turn.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !assistantText.isEmpty {
                let assistantMessage = ChatMessage(
                    id: UUID(),
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
}
