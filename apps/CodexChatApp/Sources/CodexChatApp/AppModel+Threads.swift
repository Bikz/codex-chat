import AppKit
import CodexChatCore
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
            projectStatusMessage = "No archived chat file found for the selected thread yet."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
        projectStatusMessage = "Revealed \(archiveURL.lastPathComponent) in Finder."
    }

    func selectProject(_ projectID: UUID?) {
        Task {
            selectedProjectID = projectID
            selectedThreadID = nil
            appendLog(.debug, "Selected project: \(projectID?.uuidString ?? "none")")

            do {
                try await persistSelection()
                try await refreshThreads()
                try await refreshSkills()
                refreshModsSurface()
                if let selectedThreadID {
                    try await refreshFollowUpQueue(threadID: selectedThreadID)
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
        createThread(in: projectID)
    }

    func createThread(in projectID: UUID) {
        Task {
            guard let threadRepository else { return }
            do {
                let baseCount = if selectedProjectID == projectID {
                    threads.count
                } else if generalProject?.id == projectID {
                    generalThreads.count
                } else {
                    try await threadRepository.listThreads(projectID: projectID).count
                }

                let title = "Thread \(baseCount + 1)"
                let thread = try await threadRepository.createThread(projectID: projectID, title: title)
                appendLog(.info, "Created thread \(thread.title)")

                try await chatSearchRepository?.indexThreadTitle(
                    threadID: thread.id,
                    projectID: projectID,
                    title: thread.title
                )

                selectedProjectID = projectID
                detailDestination = .thread

                if generalProject?.id == projectID {
                    try await refreshGeneralThreads(generalProjectID: projectID)
                } else {
                    try await refreshThreads()
                }
                try await refreshArchivedThreads()
                selectedThreadID = thread.id
                try await persistSelection()
                try await refreshFollowUpQueue(threadID: thread.id)
                refreshConversationState()
            } catch {
                threadsState = .failed(error.localizedDescription)
                appendLog(.error, "Create thread failed: \(error.localizedDescription)")
            }
        }
    }

    func createGeneralThread() {
        Task {
            guard let generalProjectID = generalProject?.id,
                  let threadRepository else { return }
            do {
                let title = "New chat"
                let thread = try await threadRepository.createThread(projectID: generalProjectID, title: title)
                appendLog(.info, "Created general thread \(thread.title)")

                try await chatSearchRepository?.indexThreadTitle(
                    threadID: thread.id,
                    projectID: generalProjectID,
                    title: thread.title
                )

                selectedProjectID = generalProjectID
                try await refreshGeneralThreads()
                selectedThreadID = thread.id
                detailDestination = .thread
                try await persistSelection()
                try await refreshFollowUpQueue(threadID: thread.id)
                refreshConversationState()
            } catch {
                appendLog(.error, "Create general thread failed: \(error.localizedDescription)")
            }
        }
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
                guard let thread = try await threadRepository.getThread(id: threadID) else {
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
        Task {
            selectedThreadID = threadID
            if threadID != nil {
                detailDestination = .thread
            }
            appendLog(.debug, "Selected thread: \(threadID?.uuidString ?? "none")")
            do {
                try await persistSelection()
                if let threadID {
                    try await refreshFollowUpQueue(threadID: threadID)
                }
                refreshConversationState()
                requestAutoDrain(reason: "thread selection changed")
            } catch {
                conversationState = .failed(error.localizedDescription)
                appendLog(.error, "Select thread failed: \(error.localizedDescription)")
            }
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
}
