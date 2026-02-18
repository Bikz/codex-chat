import AppKit
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

    enum RuntimeIssue: Equatable {
        case installCodex
        case recoverable(String)

        var message: String {
            switch self {
            case .installCodex:
                return "Codex CLI is not installed or not on PATH. Install Codex, then restart the runtime."
            case .recoverable(let detail):
                return detail
            }
        }
    }

    private struct ActiveTurnContext {
        var localThreadID: UUID
        var runtimeThreadID: String
        var turnID: String?
    }

    @Published var projectsState: SurfaceState<[ProjectRecord]> = .loading
    @Published var threadsState: SurfaceState<[ThreadRecord]> = .idle
    @Published var conversationState: SurfaceState<[TranscriptEntry]> = .idle

    @Published var selectedProjectID: UUID?
    @Published var selectedThreadID: UUID?
    @Published var composerText = ""

    @Published var isDiagnosticsVisible = false
    @Published var runtimeStatus: RuntimeStatus = .idle
    @Published var runtimeIssue: RuntimeIssue?
    @Published var accountState: RuntimeAccountState = .signedOut
    @Published var accountStatusMessage: String?
    @Published var isAccountOperationInProgress = false
    @Published var isAPIKeyPromptVisible = false
    @Published var pendingAPIKey = ""
    @Published private(set) var logs: [LogEntry] = []

    private let projectRepository: (any ProjectRepository)?
    private let threadRepository: (any ThreadRepository)?
    private let preferenceRepository: (any PreferenceRepository)?
    private let runtimeThreadMappingRepository: (any RuntimeThreadMappingRepository)?
    private let projectSecretRepository: (any ProjectSecretRepository)?
    private let runtime: CodexRuntime?
    private let keychainStore: APIKeychainStore

    private var transcriptStore: [UUID: [TranscriptEntry]] = [:]
    private var assistantMessageIDsByItemID: [UUID: [String: UUID]] = [:]
    private var activeTurnContext: ActiveTurnContext?
    private var runtimeEventTask: Task<Void, Never>?

    init(repositories: MetadataRepositories?, runtime: CodexRuntime?, bootError: String?) {
        self.projectRepository = repositories?.projectRepository
        self.threadRepository = repositories?.threadRepository
        self.preferenceRepository = repositories?.preferenceRepository
        self.runtimeThreadMappingRepository = repositories?.runtimeThreadMappingRepository
        self.projectSecretRepository = repositories?.projectSecretRepository
        self.runtime = runtime
        self.keychainStore = APIKeychainStore()

        if let bootError {
            self.projectsState = .failed(bootError)
            self.threadsState = .failed(bootError)
            self.conversationState = .failed(bootError)
            runtimeStatus = .error
            runtimeIssue = .recoverable(bootError)
            appendLog(.error, bootError)
        } else {
            appendLog(.info, "App model initialized")
        }
    }

    deinit {
        runtimeEventTask?.cancel()
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

    var canSendMessages: Bool {
        selectedThreadID != nil && runtimeIssue == nil && runtimeStatus == .connected
    }

    var accountSummaryText: String {
        guard let account = accountState.account else {
            return "Signed out"
        }

        switch account.type.lowercased() {
        case "chatgpt":
            if let email = account.email, let plan = account.planType {
                return "ChatGPT (\(plan)) - \(email)"
            }
            if let email = account.email {
                return "ChatGPT - \(email)"
            }
            return "ChatGPT"
        case "apikey":
            return "API key login"
        default:
            return account.type
        }
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

    func restartRuntime() {
        Task {
            await restartRuntimeSession()
        }
    }

    func signInWithChatGPT() {
        guard let runtime else { return }

        isAccountOperationInProgress = true
        accountStatusMessage = nil

        Task {
            defer { isAccountOperationInProgress = false }

            do {
                let loginStart = try await runtime.startChatGPTLogin()
                NSWorkspace.shared.open(loginStart.authURL)
                accountStatusMessage = "Complete sign-in in your browser."
                appendLog(.info, "Started ChatGPT login flow")
            } catch {
                accountStatusMessage = "ChatGPT sign-in failed: \(error.localizedDescription)"
                handleRuntimeError(error)
            }
        }
    }

    func presentAPIKeyPrompt() {
        pendingAPIKey = ""
        isAPIKeyPromptVisible = true
    }

    func cancelAPIKeyPrompt() {
        pendingAPIKey = ""
        isAPIKeyPromptVisible = false
    }

    func submitAPIKeyLogin() {
        let apiKey = pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingAPIKey = ""
        isAPIKeyPromptVisible = false

        guard !apiKey.isEmpty else {
            accountStatusMessage = "API key was empty."
            return
        }

        signInWithAPIKey(apiKey)
    }

    func signInWithAPIKey(_ apiKey: String) {
        guard let runtime else { return }

        isAccountOperationInProgress = true
        accountStatusMessage = nil

        Task {
            defer { isAccountOperationInProgress = false }

            do {
                try await runtime.startAPIKeyLogin(apiKey: apiKey)
                try keychainStore.saveSecret(apiKey, account: APIKeychainStore.runtimeAPIKeyAccount)
                try await upsertProjectAPIKeyReferenceIfNeeded()
                try await refreshAccountState()
                accountStatusMessage = "Signed in with API key."
                appendLog(.info, "Signed in with API key")
            } catch {
                accountStatusMessage = "API key sign-in failed: \(error.localizedDescription)"
                handleRuntimeError(error)
            }
        }
    }

    func logoutAccount() {
        guard let runtime else { return }

        isAccountOperationInProgress = true
        accountStatusMessage = nil

        Task {
            defer { isAccountOperationInProgress = false }

            do {
                try await runtime.logoutAccount()
                try keychainStore.deleteSecret(account: APIKeychainStore.runtimeAPIKeyAccount)
                try await refreshAccountState()
                accountStatusMessage = "Logged out."
                appendLog(.info, "Account logged out")
            } catch {
                accountStatusMessage = "Logout failed: \(error.localizedDescription)"
                handleRuntimeError(error)
            }
        }
    }

    func launchDeviceCodeLogin() {
        do {
            try CodexRuntime.launchDeviceAuthInTerminal()
            accountStatusMessage = "Device-auth started in Terminal. Availability depends on workspace settings."
            appendLog(.info, "Launched device-auth login in Terminal")
        } catch {
            accountStatusMessage = "Unable to start device-auth login: \(error.localizedDescription)"
            handleRuntimeError(error)
        }
    }

    func copyDiagnosticsBundle() {
        do {
            let snapshot = DiagnosticsBundleSnapshot(
                generatedAt: Date(),
                runtimeStatus: runtimeStatus,
                runtimeIssue: runtimeIssue?.message,
                accountSummary: accountSummaryText,
                logs: logs
            )
            let bundleURL = try DiagnosticsBundleExporter.export(snapshot: snapshot)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bundleURL.path, forType: .string)
            accountStatusMessage = "Diagnostics bundle created and copied: \(bundleURL.lastPathComponent)"
            appendLog(.info, "Diagnostics bundle exported")
        } catch DiagnosticsBundleExporterError.cancelled {
            appendLog(.debug, "Diagnostics export cancelled")
        } catch {
            accountStatusMessage = "Failed to export diagnostics: \(error.localizedDescription)"
            appendLog(.error, "Diagnostics export failed: \(error.localizedDescription)")
        }
    }

    func loadInitialData() async {
        appendLog(.info, "Loading initial metadata")
        projectsState = .loading

        do {
            try await refreshProjects()
            try await restoreLastOpenedContext()
            try await refreshThreads()
            refreshConversationState()
            appendLog(.info, "Initial metadata load completed")
        } catch {
            let message = error.localizedDescription
            projectsState = .failed(message)
            threadsState = .failed(message)
            conversationState = .failed(message)
            runtimeStatus = .error
            runtimeIssue = .recoverable(message)
            appendLog(.error, "Failed to load initial data: \(message)")
            return
        }

        await startRuntimeSession()
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
              let runtime,
              canSendMessages else {
            return
        }

        let trimmedText = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        composerText = ""
        appendEntry(.message(ChatMessage(threadId: selectedThreadID, role: .user, text: trimmedText)), to: selectedThreadID)

        Task {
            do {
                let runtimeThreadID = try await ensureRuntimeThreadID(for: selectedThreadID)
                activeTurnContext = ActiveTurnContext(
                    localThreadID: selectedThreadID,
                    runtimeThreadID: runtimeThreadID,
                    turnID: nil
                )

                let turnID = try await runtime.startTurn(threadID: runtimeThreadID, text: trimmedText)
                activeTurnContext?.turnID = turnID
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

    private func startRuntimeSession() async {
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
            appendLog(.info, "Runtime connected")
            try await refreshAccountState()
        } catch {
            handleRuntimeError(error)
        }
    }

    private func restartRuntimeSession() async {
        guard let runtime else { return }

        runtimeStatus = .starting
        runtimeIssue = nil

        do {
            try await runtime.restart()
            runtimeStatus = .connected
            runtimeIssue = nil
            appendLog(.info, "Runtime restarted")
            try await refreshAccountState()
        } catch {
            handleRuntimeError(error)
        }
    }

    private func startRuntimeEventLoopIfNeeded() async {
        guard runtimeEventTask == nil,
              let runtime else {
            return
        }

        let stream = await runtime.events()
        runtimeEventTask = Task { [weak self] in
            guard let self else { return }

            for await event in stream {
                self.handleRuntimeEvent(event)
            }
        }
    }

    private func handleRuntimeEvent(_ event: CodexRuntimeEvent) {
        switch event {
        case .threadStarted(let threadID):
            appendLog(.debug, "Runtime thread started: \(threadID)")

        case .turnStarted(let turnID):
            if var context = activeTurnContext {
                context.turnID = turnID
                activeTurnContext = context
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

        case .assistantMessageDelta(let itemID, let delta):
            guard let context = activeTurnContext else {
                appendLog(.debug, "Dropped delta with no active turn")
                return
            }

            appendAssistantDelta(delta, itemID: itemID, to: context.localThreadID)

        case .action(let action):
            if action.method == "runtime/stderr" {
                appendLog(.warning, action.detail)
            }

            guard let context = activeTurnContext else {
                appendLog(.debug, "Runtime action without active turn: \(action.method)")
                return
            }

            appendEntry(
                .actionCard(
                    ActionCard(
                        threadID: context.localThreadID,
                        method: action.method,
                        title: action.title,
                        detail: action.detail
                    )
                ),
                to: context.localThreadID
            )

        case .turnCompleted(let completion):
            if let context = activeTurnContext {
                let detail: String
                if let errorMessage = completion.errorMessage {
                    detail = "status=\(completion.status), error=\(errorMessage)"
                } else {
                    detail = "status=\(completion.status)"
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
                activeTurnContext = nil
            }

        case .accountUpdated(let authMode):
            appendLog(.info, "Account mode updated: \(authMode.rawValue)")
            Task {
                try? await refreshAccountState()
            }

        case .accountLoginCompleted(let completion):
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

    private func ensureRuntimeThreadID(for localThreadID: UUID) async throws -> String {
        if let runtimeThreadMappingRepository,
           let existingRuntimeThreadID = try await runtimeThreadMappingRepository.getRuntimeThreadID(localThreadID: localThreadID) {
            return existingRuntimeThreadID
        }

        guard let runtime else {
            throw CodexRuntimeError.processNotRunning
        }

        let runtimeThreadID = try await runtime.startThread()
        try await runtimeThreadMappingRepository?.setRuntimeThreadID(
            localThreadID: localThreadID,
            runtimeThreadID: runtimeThreadID
        )

        appendLog(.info, "Mapped local thread \(localThreadID.uuidString) to runtime thread \(runtimeThreadID)")
        return runtimeThreadID
    }

    private func refreshAccountState() async throws {
        guard let runtime else {
            accountState = .signedOut
            return
        }

        accountState = try await runtime.readAccount()
    }

    private func upsertProjectAPIKeyReferenceIfNeeded() async throws {
        guard let projectID = selectedProjectID,
              let projectSecretRepository else {
            return
        }

        _ = try await projectSecretRepository.upsertSecret(
            projectID: projectID,
            name: "OPENAI_API_KEY",
            keychainAccount: APIKeychainStore.runtimeAPIKeyAccount
        )
    }

    private func appendEntry(_ entry: TranscriptEntry, to threadID: UUID) {
        transcriptStore[threadID, default: []].append(entry)
        refreshConversationState()
    }

    private func appendAssistantDelta(_ delta: String, itemID: String, to threadID: UUID) {
        var entries = transcriptStore[threadID, default: []]
        var itemMap = assistantMessageIDsByItemID[threadID, default: [:]]

        if let messageID = itemMap[itemID],
           let index = entries.firstIndex(where: {
               guard case .message(let message) = $0 else {
                   return false
               }
               return message.id == messageID
           }),
           case .message(var existingMessage) = entries[index] {
            existingMessage.text += delta
            entries[index] = .message(existingMessage)
            transcriptStore[threadID] = entries
            refreshConversationState()
            return
        }

        let message = ChatMessage(threadId: threadID, role: .assistant, text: delta)
        entries.append(.message(message))
        itemMap[itemID] = message.id

        transcriptStore[threadID] = entries
        assistantMessageIDsByItemID[threadID] = itemMap
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

        let entries = transcriptStore[selectedThreadID, default: []]
        conversationState = .loaded(entries)
    }

    private func handleRuntimeError(_ error: Error) {
        runtimeStatus = .error

        if let runtimeError = error as? CodexRuntimeError {
            switch runtimeError {
            case .binaryNotFound:
                runtimeIssue = .installCodex
            case .handshakeFailed(let detail):
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

    private func appendLog(_ level: LogLevel, _ message: String) {
        logs.append(LogEntry(level: level, message: redactSensitiveText(in: message)))
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    private func redactSensitiveText(in text: String) -> String {
        var sanitized = text
        let patterns = [
            "sk-[A-Za-z0-9_-]{16,}",
            "(?i)api[_-]?key\\s*[:=]\\s*[^\\s]+",
            "(?i)authorization\\s*:\\s*bearer\\s+[^\\s]+"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(in: sanitized, range: range, withTemplate: "[REDACTED]")
        }

        return sanitized
    }
}
