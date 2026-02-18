import CodexChatCore
import CodexChatInfra
import CodexKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum SurfaceState<Value> {
        case idle
        case loading
        case loaded(Value)
        case failed(String)
    }

    @Published var projectsState: SurfaceState<[ProjectRecord]> = .loading
    @Published var threadsState: SurfaceState<[ThreadRecord]> = .idle
    @Published var conversationState: SurfaceState<[ChatMessage]> = .idle

    @Published var selectedProjectID: UUID?
    @Published var selectedThreadID: UUID?
    @Published var composerText = ""

    @Published var isDiagnosticsVisible = false
    @Published var runtimeStatus: RuntimeStatus = .idle
    @Published private(set) var logs: [LogEntry] = []

    private let projectRepository: (any ProjectRepository)?
    private let threadRepository: (any ThreadRepository)?
    private let preferenceRepository: (any PreferenceRepository)?

    private var messageStore: [UUID: [ChatMessage]] = [:]

    init(repositories: MetadataRepositories?, bootError: String?) {
        self.projectRepository = repositories?.projectRepository
        self.threadRepository = repositories?.threadRepository
        self.preferenceRepository = repositories?.preferenceRepository

        if let bootError {
            self.projectsState = .failed(bootError)
            self.threadsState = .failed(bootError)
            self.conversationState = .failed(bootError)
            runtimeStatus = .error
            appendLog(.error, bootError)
        } else {
            appendLog(.info, "App model initialized")
        }
    }

    var projects: [ProjectRecord] {
        if case .loaded(let projects) = projectsState {
            return projects
        }
        return []
    }

    var threads: [ThreadRecord] {
        if case .loaded(let threads) = threadsState {
            return threads
        }
        return []
    }

    func onAppear() {
        Task {
            await loadInitialData()
        }
    }

    func toggleDiagnostics() {
        isDiagnosticsVisible.toggle()
        appendLog(.debug, "Diagnostics toggled: \(isDiagnosticsVisible)")
    }

    func closeDiagnostics() {
        isDiagnosticsVisible = false
    }

    func retryLoad() {
        Task {
            await loadInitialData()
        }
    }

    func loadInitialData() async {
        runtimeStatus = .starting
        appendLog(.info, "Loading initial metadata")
        projectsState = .loading

        do {
            try await refreshProjects()
            try await restoreLastOpenedContext()
            try await refreshThreads()
            refreshConversationState()
            runtimeStatus = .connected
            appendLog(.info, "Initial metadata load completed")
        } catch {
            let message = error.localizedDescription
            projectsState = .failed(message)
            threadsState = .failed(message)
            conversationState = .failed(message)
            runtimeStatus = .error
            appendLog(.error, "Failed to load initial data: \(message)")
        }
    }

    func createProject() {
        Task {
            guard let projectRepository else { return }
            do {
                let name = "Project \(projects.count + 1)"
                let project = try await projectRepository.createProject(named: name)
                appendLog(.info, "Created project \(project.name)")

                try await refreshProjects()
                selectedProjectID = project.id
                try await persistSelection()
                try await refreshThreads()
                refreshConversationState()
            } catch {
                projectsState = .failed(error.localizedDescription)
                appendLog(.error, "Create project failed: \(error.localizedDescription)")
            }
        }
    }

    func selectProject(_ projectID: UUID?) {
        Task {
            selectedProjectID = projectID
            selectedThreadID = nil
            appendLog(.debug, "Selected project: \(projectID?.uuidString ?? "none")")

            do {
                try await persistSelection()
                try await refreshThreads()
                refreshConversationState()
            } catch {
                threadsState = .failed(error.localizedDescription)
                appendLog(.error, "Select project failed: \(error.localizedDescription)")
            }
        }
    }

    func createThread() {
        Task {
            guard let projectID = selectedProjectID, let threadRepository else { return }
            do {
                let title = "Thread \(threads.count + 1)"
                let thread = try await threadRepository.createThread(projectID: projectID, title: title)
                appendLog(.info, "Created thread \(thread.title)")

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

    func sendMessage() {
        guard let selectedThreadID,
              !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let userText = composerText
        composerText = ""

        let userMessage = ChatMessage(threadId: selectedThreadID, role: .user, text: userText)
        let assistantMessage = ChatMessage(
            threadId: selectedThreadID,
            role: .assistant,
            text: "Acknowledged. Runtime integration will stream real responses in a later epic."
        )

        messageStore[selectedThreadID, default: []].append(userMessage)
        messageStore[selectedThreadID, default: []].append(assistantMessage)
        appendLog(.info, "Queued placeholder response for thread \(selectedThreadID.uuidString)")
        refreshConversationState()
    }

    private func refreshProjects() async throws {
        guard let projectRepository else {
            projectsState = .failed("Project repository is unavailable.")
            return
        }

        let loadedProjects = try await projectRepository.listProjects()
        projectsState = .loaded(loadedProjects)

        if selectedProjectID == nil {
            selectedProjectID = loadedProjects.first?.id
        }
    }

    private func refreshThreads() async throws {
        guard let threadRepository else {
            threadsState = .failed("Thread repository is unavailable.")
            return
        }

        guard let selectedProjectID else {
            threadsState = .loaded([])
            return
        }

        threadsState = .loading
        let loadedThreads = try await threadRepository.listThreads(projectID: selectedProjectID)
        threadsState = .loaded(loadedThreads)

        if let selectedThreadID,
           loadedThreads.contains(where: { $0.id == selectedThreadID }) {
            return
        }

        self.selectedThreadID = loadedThreads.first?.id
    }

    private func restoreLastOpenedContext() async throws {
        guard let preferenceRepository else { return }

        if let projectIDString = try await preferenceRepository.getPreference(key: .lastOpenedProjectID),
           let projectID = UUID(uuidString: projectIDString) {
            selectedProjectID = projectID
        }

        if let threadIDString = try await preferenceRepository.getPreference(key: .lastOpenedThreadID),
           let threadID = UUID(uuidString: threadIDString) {
            selectedThreadID = threadID
        }

        appendLog(.debug, "Restored last-opened context")
    }

    private func persistSelection() async throws {
        guard let preferenceRepository else { return }

        if let selectedProjectID {
            try await preferenceRepository.setPreference(key: .lastOpenedProjectID, value: selectedProjectID.uuidString)
        }

        if let selectedThreadID {
            try await preferenceRepository.setPreference(key: .lastOpenedThreadID, value: selectedThreadID.uuidString)
        }
    }

    private func refreshConversationState() {
        guard let selectedThreadID else {
            conversationState = .idle
            return
        }

        let messages = messageStore[selectedThreadID, default: []]
        conversationState = .loaded(messages)
    }

    private func appendLog(_ level: LogLevel, _ message: String) {
        logs.append(LogEntry(level: level, message: message))
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }
}
