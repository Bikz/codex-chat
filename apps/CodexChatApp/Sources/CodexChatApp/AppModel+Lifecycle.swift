import Foundation

extension AppModel {
    func onAppear() {
        Task {
            await loadInitialData()
        }
    }

    func retryLoad() {
        Task {
            await loadInitialData()
        }
    }

    func restartRuntime() {
        Task {
            await restartRuntimeSession()
        }
    }

    func loadInitialData() async {
        appendLog(.info, "Loading initial metadata")
        projectsState = .loading

        do {
            try await refreshProjects()
            try await ensureGeneralProject()
            try await restoreLastOpenedContext()
            try await validateAndRepairProjectsOnLaunch()
            try await refreshThreads()
            try await refreshGeneralThreads()
            try await refreshArchivedThreads()
            try await refreshFollowUpQueuesForVisibleThreads()
            try await refreshSkills()
            refreshModsSurface()
            refreshConversationState()
            appendLog(.info, "Initial metadata load completed")
        } catch {
            let message = error.localizedDescription
            projectsState = .failed(message)
            threadsState = .failed(message)
            archivedThreadsState = .failed(message)
            conversationState = .failed(message)
            skillsState = .failed(message)
            runtimeStatus = .error
            runtimeIssue = .recoverable(message)
            appendLog(.error, "Failed to load initial data: \(message)")
            return
        }

        await startRuntimeSession()
    }
}
