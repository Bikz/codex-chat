import AppKit
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
                refreshConversationState()
            } catch {
                threadsState = .failed(error.localizedDescription)
                appendLog(.error, "Select project failed: \(error.localizedDescription)")
            }
        }
    }

    func createThread() {
        Task {
            guard let projectID = selectedProjectID,
                  let threadRepository else { return }
            do {
                let title = "Thread \(threads.count + 1)"
                let thread = try await threadRepository.createThread(projectID: projectID, title: title)
                appendLog(.info, "Created thread \(thread.title)")

                try await chatSearchRepository?.indexThreadTitle(
                    threadID: thread.id,
                    projectID: projectID,
                    title: thread.title
                )

                try await refreshThreads()
                selectedThreadID = thread.id
                try await persistSelection()
                refreshConversationState()
            } catch {
                threadsState = .failed(error.localizedDescription)
                appendLog(.error, "Create thread failed: \(error.localizedDescription)")
            }
        }
    }

    func selectThread(_ threadID: UUID?) {
        Task {
            selectedThreadID = threadID
            appendLog(.debug, "Selected thread: \(threadID?.uuidString ?? "none")")
            do {
                try await persistSelection()
                refreshConversationState()
            } catch {
                conversationState = .failed(error.localizedDescription)
                appendLog(.error, "Select thread failed: \(error.localizedDescription)")
            }
        }
    }
}
