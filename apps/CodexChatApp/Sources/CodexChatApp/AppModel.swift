import CodexChatCore
import CodexChatInfra
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var projects: [ProjectRecord] = []
    @Published var threads: [ThreadRecord] = []
    @Published var selectedProjectID: UUID?
    @Published var selectedThreadID: UUID?
    @Published var composerText = ""
    @Published var bootError: String?

    private let projectRepository: (any ProjectRepository)?
    private let threadRepository: (any ThreadRepository)?
    private let preferenceRepository: (any PreferenceRepository)?

    private var messageStore: [UUID: [ChatMessage]] = [:]

    init(repositories: MetadataRepositories?, bootError: String?) {
        self.projectRepository = repositories?.projectRepository
        self.threadRepository = repositories?.threadRepository
        self.preferenceRepository = repositories?.preferenceRepository
        self.bootError = bootError
    }

    func onAppear() {
        Task {
            await loadInitialData()
        }
    }

    func loadInitialData() async {
        do {
            try await refreshProjects()
            try await restoreLastOpenedContext()
            try await refreshThreads()
        } catch {
            bootError = error.localizedDescription
        }
    }

    func createProject() {
        Task {
            guard let projectRepository else { return }
            do {
                let name = "Project \(projects.count + 1)"
                let project = try await projectRepository.createProject(named: name)
                try await refreshProjects()
                selectedProjectID = project.id
                try await persistSelection()
                try await refreshThreads()
            } catch {
                bootError = error.localizedDescription
            }
        }
    }

    func selectProject(_ projectID: UUID?) {
        Task {
            selectedProjectID = projectID
            selectedThreadID = nil
            do {
                try await persistSelection()
                try await refreshThreads()
            } catch {
                bootError = error.localizedDescription
            }
        }
    }

    func createThread() {
        Task {
            guard let projectID = selectedProjectID, let threadRepository else { return }
            do {
                let title = "Thread \(threads.count + 1)"
                let thread = try await threadRepository.createThread(projectID: projectID, title: title)
                try await refreshThreads()
                selectedThreadID = thread.id
                try await persistSelection()
            } catch {
                bootError = error.localizedDescription
            }
        }
    }

    func selectThread(_ threadID: UUID?) {
        Task {
            selectedThreadID = threadID
            do {
                try await persistSelection()
            } catch {
                bootError = error.localizedDescription
            }
        }
    }

    func messagesForSelectedThread() -> [ChatMessage] {
        guard let selectedThreadID else { return [] }
        return messageStore[selectedThreadID, default: []]
    }

    func sendMessage() {
        guard let selectedThreadID, !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
        objectWillChange.send()
    }

    private func refreshProjects() async throws {
        guard let projectRepository else { return }
        projects = try await projectRepository.listProjects()

        if selectedProjectID == nil {
            selectedProjectID = projects.first?.id
        }
    }

    private func refreshThreads() async throws {
        guard let threadRepository, let selectedProjectID else {
            threads = []
            return
        }

        threads = try await threadRepository.listThreads(projectID: selectedProjectID)

        if let selectedThreadID, threads.contains(where: { $0.id == selectedThreadID }) {
            return
        }

        selectedThreadID = threads.first?.id
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
}
