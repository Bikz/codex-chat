import AppKit
import CodexChatCore
import CodexChatInfra
import CodexKit
import CodexMemory
import CodexMods
import CodexSkills
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum NavigationSection: String, CaseIterable {
        case chats
        case skills
        case memory
        case mods
    }

    struct SkillListItem: Identifiable, Hashable {
        let skill: DiscoveredSkill
        var isEnabledForProject: Bool

        var id: String {
            skill.id
        }
    }

    struct ModsSurfaceModel: Hashable {
        var globalMods: [DiscoveredUIMod]
        var projectMods: [DiscoveredUIMod]
        var selectedGlobalModPath: String?
        var selectedProjectModPath: String?
    }

    struct PendingModReview: Identifiable, Hashable {
        let id: UUID
        let threadID: UUID
        let changes: [RuntimeFileChange]
        let reason: String
        let canRevert: Bool
    }

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
                "Codex CLI is not installed or not on PATH. Install Codex, then restart the runtime."
            case let .recoverable(detail):
                detail
            }
        }
    }

    private struct ActiveTurnContext {
        var localThreadID: UUID
        var projectID: UUID
        var projectPath: String
        var runtimeThreadID: String
        var userText: String
        var assistantText: String
        var actions: [ActionCard]
        var startedAt: Date
    }

    @Published var projectsState: SurfaceState<[ProjectRecord]> = .loading
    @Published var threadsState: SurfaceState<[ThreadRecord]> = .idle
    @Published var conversationState: SurfaceState<[TranscriptEntry]> = .idle
    @Published var searchState: SurfaceState<[ChatSearchResult]> = .idle
    @Published var skillsState: SurfaceState<[SkillListItem]> = .idle
    @Published var modsState: SurfaceState<ModsSurfaceModel> = .idle

    @Published var selectedProjectID: UUID?
    @Published var selectedThreadID: UUID?
    @Published var navigationSection: NavigationSection = .chats
    @Published var composerText = ""
    @Published var searchQuery = ""
    @Published var selectedSkillIDForComposer: String?

    @Published var isDiagnosticsVisible = false
    @Published var isProjectSettingsVisible = false
    @Published var isLogsDrawerVisible = false
    @Published var isReviewChangesVisible = false
    @Published var runtimeStatus: RuntimeStatus = .idle
    @Published var runtimeIssue: RuntimeIssue?
    @Published var accountState: RuntimeAccountState = .signedOut
    @Published var accountStatusMessage: String?
    @Published var approvalStatusMessage: String?
    @Published var projectStatusMessage: String?
    @Published var skillStatusMessage: String?
    @Published var memoryStatusMessage: String?
    @Published var modStatusMessage: String?
    @Published var isAccountOperationInProgress = false
    @Published var isApprovalDecisionInProgress = false
    @Published var isSkillOperationInProgress = false
    @Published var isAPIKeyPromptVisible = false
    @Published var pendingAPIKey = ""
    @Published var activeApprovalRequest: RuntimeApprovalRequest?
    @Published var pendingModReview: PendingModReview?
    @Published var isModReviewDecisionInProgress = false
    @Published private(set) var isTurnInProgress = false
    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var threadLogsByThreadID: [UUID: [ThreadLogEntry]] = [:]
    @Published private(set) var reviewChangesByThreadID: [UUID: [RuntimeFileChange]] = [:]
    @Published private(set) var isNodeSkillInstallerAvailable = false

    @Published private(set) var effectiveThemeOverride: ModThemeOverride = .init()

    private let projectRepository: (any ProjectRepository)?
    private let threadRepository: (any ThreadRepository)?
    private let preferenceRepository: (any PreferenceRepository)?
    private let runtimeThreadMappingRepository: (any RuntimeThreadMappingRepository)?
    private let projectSecretRepository: (any ProjectSecretRepository)?
    private let projectSkillEnablementRepository: (any ProjectSkillEnablementRepository)?
    private let chatSearchRepository: (any ChatSearchRepository)?
    private let runtime: CodexRuntime?
    private let skillCatalogService: SkillCatalogService
    private let modDiscoveryService: UIModDiscoveryService
    private let keychainStore: APIKeychainStore

    private var transcriptStore: [UUID: [TranscriptEntry]] = [:]
    private var assistantMessageIDsByItemID: [UUID: [String: UUID]] = [:]
    private var runtimeThreadIDByLocalThreadID: [UUID: String] = [:]
    private var localThreadIDByRuntimeThreadID: [String: UUID] = [:]
    private var localThreadIDByCommandItemID: [String: UUID] = [:]
    private var approvalStateMachine = ApprovalStateMachine()
    private var activeTurnContext: ActiveTurnContext?
    private var activeModSnapshot: ModEditSafety.Snapshot?
    private var runtimeEventTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var modsRefreshTask: Task<Void, Never>?
    private var modsDebounceTask: Task<Void, Never>?

    private var globalModsWatcher: DirectoryWatcher?
    private var projectModsWatcher: DirectoryWatcher?
    private var watchedProjectModsRootPath: String?

    init(
        repositories: MetadataRepositories?,
        runtime: CodexRuntime?,
        bootError: String?,
        skillCatalogService: SkillCatalogService = SkillCatalogService(),
        modDiscoveryService: UIModDiscoveryService = UIModDiscoveryService()
    ) {
        projectRepository = repositories?.projectRepository
        threadRepository = repositories?.threadRepository
        preferenceRepository = repositories?.preferenceRepository
        runtimeThreadMappingRepository = repositories?.runtimeThreadMappingRepository
        projectSecretRepository = repositories?.projectSecretRepository
        projectSkillEnablementRepository = repositories?.projectSkillEnablementRepository
        chatSearchRepository = repositories?.chatSearchRepository
        self.runtime = runtime
        self.skillCatalogService = skillCatalogService
        self.modDiscoveryService = modDiscoveryService
        keychainStore = APIKeychainStore()
        isNodeSkillInstallerAvailable = skillCatalogService.isNodeInstallerAvailable()

        if let bootError {
            projectsState = .failed(bootError)
            threadsState = .failed(bootError)
            conversationState = .failed(bootError)
            skillsState = .failed(bootError)
            runtimeStatus = .error
            runtimeIssue = .recoverable(bootError)
            appendLog(.error, bootError)
        } else {
            appendLog(.info, "App model initialized")
        }
    }

    deinit {
        runtimeEventTask?.cancel()
        searchTask?.cancel()
        modsRefreshTask?.cancel()
        modsDebounceTask?.cancel()
        globalModsWatcher?.stop()
        projectModsWatcher?.stop()
    }

    var projects: [ProjectRecord] {
        if case let .loaded(projects) = projectsState {
            return projects
        }
        return []
    }

    var threads: [ThreadRecord] {
        if case let .loaded(threads) = threadsState {
            return threads
        }
        return []
    }

    var canSendMessages: Bool {
        selectedThreadID != nil
            && runtimeIssue == nil
            && runtimeStatus == .connected
            && pendingModReview == nil
            && activeApprovalRequest == nil
            && !isApprovalDecisionInProgress
            && !isTurnInProgress
            && isSignedInForRuntime
    }

    var isSignedInForRuntime: Bool {
        !accountState.requiresOpenAIAuth || accountState.account != nil
    }

    var selectedProject: ProjectRecord? {
        guard let selectedProjectID else { return nil }
        return projects.first(where: { $0.id == selectedProjectID })
    }

    var isSelectedProjectTrusted: Bool {
        selectedProject?.trustState == .trusted
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

    var skills: [SkillListItem] {
        if case let .loaded(skills) = skillsState {
            return skills
        }
        return []
    }

    var enabledSkillsForSelectedProject: [SkillListItem] {
        skills.filter(\.isEnabledForProject)
    }

    var selectedSkillForComposer: SkillListItem? {
        guard let selectedSkillIDForComposer else { return nil }
        return skills.first(where: { $0.id == selectedSkillIDForComposer })
    }

    var selectedThreadLogs: [ThreadLogEntry] {
        guard let selectedThreadID else { return [] }
        return threadLogsByThreadID[selectedThreadID, default: []]
    }

    var selectedThreadChanges: [RuntimeFileChange] {
        guard let selectedThreadID else { return [] }
        return reviewChangesByThreadID[selectedThreadID, default: []]
    }

    var canReviewChanges: Bool {
        !selectedThreadChanges.isEmpty
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
            try await refreshSkills()
            refreshModsSurface()
            refreshConversationState()
            appendLog(.info, "Initial metadata load completed")
        } catch {
            let message = error.localizedDescription
            projectsState = .failed(message)
            threadsState = .failed(message)
            conversationState = .failed(message)
            skillsState = .failed(message)
            runtimeStatus = .error
            runtimeIssue = .recoverable(message)
            appendLog(.error, "Failed to load initial data: \(message)")
            return
        }

        await startRuntimeSession()
    }

    func openProjectFolder() {
        guard let projectRepository else { return }

        let panel = NSOpenPanel()
        panel.title = "Open Project Folder"
        panel.prompt = "Open Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let url = panel.url
        else {
            return
        }

        Task {
            do {
                let path = url.standardizedFileURL.path
                if let existing = try await projectRepository.getProject(path: path) {
                    selectedProjectID = existing.id
                    try await prepareProjectFolderStructure(projectPath: existing.path)
                    try await persistSelection()
                    try await refreshThreads()
                    try await ensureSelectedProjectHasDefaultThread()
                    try await refreshSkills()
                    refreshModsSurface()
                    refreshConversationState()
                    projectStatusMessage = "Opened existing project at \(path)."
                    appendLog(.info, "Opened existing project \(existing.name)")
                    return
                }

                let trustState: ProjectTrustState = Self.isGitProject(path: path) ? .trusted : .untrusted
                let project = try await projectRepository.createProject(
                    named: url.lastPathComponent,
                    path: path,
                    trustState: trustState
                )

                try await refreshProjects()
                selectedProjectID = project.id
                try await prepareProjectFolderStructure(projectPath: project.path)
                try await persistSelection()
                try await refreshThreads()
                try await ensureSelectedProjectHasDefaultThread()
                try await refreshSkills()
                refreshModsSurface()
                refreshConversationState()
                projectStatusMessage = trustState == .trusted
                    ? "Project opened and trusted (Git repository detected)."
                    : "Project opened in untrusted mode. Read-only is recommended until you trust this project."
                appendLog(.info, "Opened project \(project.name) at \(path)")
            } catch {
                projectsState = .failed(error.localizedDescription)
                appendLog(.error, "Open project failed: \(error.localizedDescription)")
            }
        }
    }

    func showProjectSettings() {
        isProjectSettingsVisible = true
    }

    func closeProjectSettings() {
        isProjectSettingsVisible = false
    }

    func toggleLogsDrawer() {
        isLogsDrawerVisible.toggle()
    }

    func openReviewChanges() {
        guard canReviewChanges else { return }
        isReviewChangesVisible = true
    }

    func closeReviewChanges() {
        isReviewChangesVisible = false
    }

    func acceptReviewChanges() {
        guard let selectedThreadID else { return }
        reviewChangesByThreadID[selectedThreadID] = []
        isReviewChangesVisible = false
        projectStatusMessage = "Accepted reviewed changes for this thread."
    }

    func revertReviewChanges() {
        guard let project = selectedProject else { return }
        let paths = Array(Set(selectedThreadChanges.map(\.path))).sorted()

        guard !paths.isEmpty else {
            projectStatusMessage = "No file paths available to revert."
            return
        }

        guard Self.isGitProject(path: project.path) else {
            projectStatusMessage = "Revert is available for Git projects only."
            return
        }

        do {
            try restorePathsWithGit(paths, projectPath: project.path)
            if let selectedThreadID {
                reviewChangesByThreadID[selectedThreadID] = []
            }
            isReviewChangesVisible = false
            projectStatusMessage = "Reverted \(paths.count) file(s) with git restore."
        } catch {
            projectStatusMessage = "Failed to revert files: \(error.localizedDescription)"
            appendLog(.error, "Revert failed: \(error.localizedDescription)")
        }
    }

    func acceptPendingModReview() {
        guard let review = pendingModReview else { return }
        pendingModReview = nil
        isModReviewDecisionInProgress = false

        if let snapshot = activeModSnapshot {
            ModEditSafety.discard(snapshot: snapshot)
            activeModSnapshot = nil
        }

        appendLog(.info, "Accepted mod changes for thread \(review.threadID.uuidString)")
        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: review.threadID,
                    method: "mods/accepted",
                    title: "Mod changes accepted",
                    detail: "Approved \(review.changes.count) mod-related change(s)."
                )
            ),
            to: review.threadID
        )
    }

    func revertPendingModReview() {
        guard let review = pendingModReview else { return }
        guard let snapshot = activeModSnapshot else {
            modStatusMessage = "Revert is unavailable (no snapshot captured)."
            return
        }

        isModReviewDecisionInProgress = true
        Task {
            defer { isModReviewDecisionInProgress = false }

            do {
                try ModEditSafety.restore(from: snapshot)
                pendingModReview = nil
                activeModSnapshot = nil
                refreshModsSurface()
                appendLog(.warning, "Reverted mod changes for thread \(review.threadID.uuidString)")
                appendEntry(
                    .actionCard(
                        ActionCard(
                            threadID: review.threadID,
                            method: "mods/reverted",
                            title: "Mod changes reverted",
                            detail: "Restored mod snapshot from \(snapshot.createdAt.formatted())."
                        )
                    ),
                    to: review.threadID
                )
            } catch {
                modStatusMessage = "Failed to revert mod changes: \(error.localizedDescription)"
                appendLog(.error, "Revert mod changes failed: \(error.localizedDescription)")
            }
        }
    }

    func approvePendingApprovalOnce() {
        submitApprovalDecision(.approveOnce)
    }

    func approvePendingApprovalForSession() {
        submitApprovalDecision(.approveForSession)
    }

    func declinePendingApproval() {
        submitApprovalDecision(.decline)
    }

    func requiresDangerConfirmation(
        sandboxMode: ProjectSandboxMode,
        approvalPolicy: ProjectApprovalPolicy
    ) -> Bool {
        sandboxMode == .dangerFullAccess || approvalPolicy == .never
    }

    var dangerConfirmationPhrase: String {
        "ENABLE UNSAFE MODE"
    }

    func updateSelectedProjectSafetySettings(
        sandboxMode: ProjectSandboxMode,
        approvalPolicy: ProjectApprovalPolicy,
        networkAccess: Bool,
        webSearch: ProjectWebSearchMode
    ) {
        guard let selectedProjectID,
              let projectRepository
        else {
            return
        }

        let settings = ProjectSafetySettings(
            sandboxMode: sandboxMode,
            approvalPolicy: approvalPolicy,
            networkAccess: networkAccess,
            webSearch: webSearch
        )

        Task {
            do {
                _ = try await projectRepository.updateProjectSafetySettings(
                    id: selectedProjectID,
                    settings: settings
                )
                try await refreshProjects()
                projectStatusMessage = "Updated safety settings for this project."
            } catch {
                projectStatusMessage = "Failed to update safety settings: \(error.localizedDescription)"
                appendLog(.error, "Failed to update safety settings: \(error.localizedDescription)")
            }
        }
    }

    func updateSelectedProjectMemorySettings(
        writeMode: ProjectMemoryWriteMode,
        embeddingsEnabled: Bool
    ) {
        guard let selectedProjectID,
              let projectRepository
        else {
            return
        }

        let settings = ProjectMemorySettings(writeMode: writeMode, embeddingsEnabled: embeddingsEnabled)
        Task {
            do {
                _ = try await projectRepository.updateProjectMemorySettings(
                    id: selectedProjectID,
                    settings: settings
                )
                try await refreshProjects()
                memoryStatusMessage = "Updated memory settings for this project."
            } catch {
                memoryStatusMessage = "Failed to update memory settings: \(error.localizedDescription)"
                appendLog(.error, "Failed to update memory settings: \(error.localizedDescription)")
            }
        }
    }

    func openSafetyPolicyDocument() {
        let url = Bundle.module.url(forResource: "SafetyPolicy", withExtension: "md")
            ?? Bundle.module.url(forResource: "SafetyPolicy", withExtension: "md", subdirectory: "Resources")
        guard let url else {
            projectStatusMessage = "Local safety document is unavailable."
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func submitApprovalDecision(_ decision: RuntimeApprovalDecision) {
        guard let request = activeApprovalRequest,
              let runtime
        else {
            return
        }

        isApprovalDecisionInProgress = true
        approvalStatusMessage = nil

        Task {
            defer { isApprovalDecisionInProgress = false }

            do {
                try await runtime.respondToApproval(requestID: request.id, decision: decision)
                _ = approvalStateMachine.resolve(id: request.id)
                activeApprovalRequest = approvalStateMachine.activeRequest
                approvalStatusMessage = "Sent decision: \(approvalDecisionLabel(decision))."
                appendLog(.info, "Approval decision sent for request \(request.id): \(approvalDecisionLabel(decision))")
            } catch {
                approvalStatusMessage = "Failed to send approval decision: \(error.localizedDescription)"
                appendLog(.error, "Approval decision failed: \(error.localizedDescription)")
            }
        }
    }

    func trustSelectedProject() {
        setSelectedProjectTrustState(.trusted)
    }

    func untrustSelectedProject() {
        setSelectedProjectTrustState(.untrusted)
    }

    func updateSearchQuery(_ query: String) {
        searchQuery = query
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchState = .idle
            return
        }

        guard let chatSearchRepository else {
            searchState = .failed("Search index is unavailable.")
            return
        }

        searchState = .loading
        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                if Task.isCancelled { return }

                let results = try await chatSearchRepository.search(query: trimmed, projectID: nil, limit: 50)
                if Task.isCancelled { return }
                searchState = .loaded(results)
            } catch is CancellationError {
                return
            } catch {
                searchState = .failed(error.localizedDescription)
                appendLog(.error, "Search failed: \(error.localizedDescription)")
            }
        }
    }

    func selectSearchResult(_ result: ChatSearchResult) {
        Task {
            selectedProjectID = result.projectID
            selectedThreadID = result.threadID
            do {
                try await persistSelection()
                try await refreshThreads()
                try await refreshSkills()
                refreshModsSurface()
                refreshConversationState()
            } catch {
                appendLog(.error, "Failed to open search result: \(error.localizedDescription)")
            }
        }
    }

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

    func refreshSkillsSurface() {
        Task {
            do {
                try await refreshSkills()
            } catch {
                skillsState = .failed(error.localizedDescription)
                skillStatusMessage = "Failed to refresh skills: \(error.localizedDescription)"
                appendLog(.error, "Refresh skills failed: \(error.localizedDescription)")
            }
        }
    }

    func isTrustedSkillSource(_ source: String) -> Bool {
        skillCatalogService.isTrustedSource(source)
    }

    func installSkill(
        source: String,
        scope: SkillInstallScope,
        installer: SkillInstallerKind
    ) {
        isSkillOperationInProgress = true
        skillStatusMessage = nil

        let request = SkillInstallRequest(
            source: source,
            scope: mapSkillScope(scope),
            projectPath: selectedProject?.path,
            installer: installer
        )

        Task {
            defer { isSkillOperationInProgress = false }
            do {
                let result = try skillCatalogService.installSkill(request)
                try await refreshSkills()
                skillStatusMessage = "Installed skill to \(result.installedPath)."
                appendLog(.info, "Installed skill from \(source)")
            } catch {
                skillStatusMessage = "Skill install failed: \(error.localizedDescription)"
                appendLog(.error, "Skill install failed: \(error.localizedDescription)")
            }
        }
    }

    func updateSkill(_ item: SkillListItem) {
        isSkillOperationInProgress = true
        skillStatusMessage = nil

        Task {
            defer { isSkillOperationInProgress = false }
            do {
                _ = try skillCatalogService.updateSkill(at: item.skill.skillPath)
                try await refreshSkills()
                skillStatusMessage = "Updated \(item.skill.name)."
                appendLog(.info, "Updated skill \(item.skill.name)")
            } catch {
                skillStatusMessage = "Skill update failed: \(error.localizedDescription)"
                appendLog(.error, "Skill update failed: \(error.localizedDescription)")
            }
        }
    }

    func setSkillEnabled(_ item: SkillListItem, enabled: Bool) {
        guard let selectedProjectID,
              let projectSkillEnablementRepository
        else {
            skillStatusMessage = "Select a project before enabling skills."
            return
        }

        Task {
            do {
                try await projectSkillEnablementRepository.setSkillEnabled(
                    projectID: selectedProjectID,
                    skillPath: item.skill.skillPath,
                    enabled: enabled
                )
                try await refreshSkills()
                if !enabled, selectedSkillIDForComposer == item.id {
                    selectedSkillIDForComposer = nil
                }
            } catch {
                skillStatusMessage = "Failed to update skill enablement: \(error.localizedDescription)"
                appendLog(.error, "Skill enablement update failed: \(error.localizedDescription)")
            }
        }
    }

    func selectSkillForComposer(_ item: SkillListItem) {
        guard item.isEnabledForProject else {
            skillStatusMessage = "Enable the skill for this project first."
            return
        }

        selectedSkillIDForComposer = item.id
        let trigger = "$\(item.skill.name)"
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(trigger) {
            composerText = trimmed.isEmpty ? trigger : "\(trimmed)\n\(trigger)"
        }
    }

    func clearSelectedSkillForComposer() {
        selectedSkillIDForComposer = nil
    }

    func refreshModsSurface() {
        modsState = .loading
        modsRefreshTask?.cancel()

        modsRefreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                let globalRoot = try Self.globalModsRootPath()
                let projectRoot = selectedProject.map { Self.projectModsRootPath(projectPath: $0.path) }

                let globalMods = try modDiscoveryService.discoverMods(in: globalRoot, scope: .global)
                let projectMods: [DiscoveredUIMod] = if let projectRoot {
                    try modDiscoveryService.discoverMods(in: projectRoot, scope: .project)
                } else {
                    []
                }

                let persistedGlobal = try await preferenceRepository?.getPreference(key: .globalUIModPath)
                let selectedGlobal = Self.normalizedOptionalPath(persistedGlobal)
                let selectedProject = Self.normalizedOptionalPath(selectedProject?.uiModPath)

                let globalOverride = globalMods.first(where: { $0.directoryPath == selectedGlobal })?.definition.theme
                let projectOverride = projectMods.first(where: { $0.directoryPath == selectedProject })?.definition.theme

                var effective = ModThemeOverride()
                if let globalOverride {
                    effective = effective.merged(with: globalOverride)
                }
                if let projectOverride {
                    effective = effective.merged(with: projectOverride)
                }

                effectiveThemeOverride = effective
                modsState = .loaded(
                    ModsSurfaceModel(
                        globalMods: globalMods,
                        projectMods: projectMods,
                        selectedGlobalModPath: selectedGlobal,
                        selectedProjectModPath: selectedProject
                    )
                )

                startModWatchersIfNeeded(globalRootPath: globalRoot, projectRootPath: projectRoot)
            } catch {
                modsState = .failed(error.localizedDescription)
                modStatusMessage = "Failed to load mods: \(error.localizedDescription)"
                appendLog(.error, "Mods refresh failed: \(error.localizedDescription)")
            }
        }
    }

    func setGlobalMod(_ mod: DiscoveredUIMod?) {
        guard let preferenceRepository else {
            modStatusMessage = "Preferences unavailable."
            return
        }

        let value = mod?.directoryPath ?? ""
        Task {
            do {
                try await preferenceRepository.setPreference(key: .globalUIModPath, value: value)
                modStatusMessage = mod == nil ? "Global mod disabled." : "Enabled global mod: \(mod?.definition.manifest.name ?? "")."
                refreshModsSurface()
            } catch {
                modStatusMessage = "Failed to update global mod: \(error.localizedDescription)"
                appendLog(.error, "Update global mod failed: \(error.localizedDescription)")
            }
        }
    }

    func setProjectMod(_ mod: DiscoveredUIMod?) {
        guard let projectRepository,
              let selectedProjectID
        else {
            modStatusMessage = "Select a project first."
            return
        }

        Task {
            do {
                _ = try await projectRepository.updateProjectUIModPath(id: selectedProjectID, uiModPath: mod?.directoryPath)
                try await refreshProjects()
                modStatusMessage = mod == nil ? "Project mod disabled." : "Enabled project mod: \(mod?.definition.manifest.name ?? "")."
                refreshModsSurface()
            } catch {
                modStatusMessage = "Failed to update project mod: \(error.localizedDescription)"
                appendLog(.error, "Update project mod failed: \(error.localizedDescription)")
            }
        }
    }

    func revealGlobalModsFolder() {
        do {
            let path = try Self.globalModsRootPath()
            let url = URL(fileURLWithPath: path, isDirectory: true)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            modStatusMessage = "Unable to reveal global mods folder: \(error.localizedDescription)"
        }
    }

    func revealProjectModsFolder() {
        guard let project = selectedProject else {
            modStatusMessage = "Select a project first."
            return
        }

        let url = URL(fileURLWithPath: Self.projectModsRootPath(projectPath: project.path), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            modStatusMessage = "Unable to reveal project mods folder: \(error.localizedDescription)"
        }
    }

    func createSampleGlobalMod() {
        do {
            let root = try Self.globalModsRootPath()
            let definitionURL = try modDiscoveryService.writeSampleMod(to: root, name: "sample-mod")
            NSWorkspace.shared.activateFileViewerSelecting([definitionURL])
            modStatusMessage = "Created sample global mod."
            refreshModsSurface()
        } catch {
            modStatusMessage = "Failed to create sample mod: \(error.localizedDescription)"
        }
    }

    func createSampleProjectMod() {
        guard let project = selectedProject else {
            modStatusMessage = "Select a project first."
            return
        }

        let root = Self.projectModsRootPath(projectPath: project.path)
        do {
            let definitionURL = try modDiscoveryService.writeSampleMod(to: root, name: "sample-mod")
            NSWorkspace.shared.activateFileViewerSelecting([definitionURL])
            modStatusMessage = "Created sample project mod."
            refreshModsSurface()
        } catch {
            modStatusMessage = "Failed to create sample mod: \(error.localizedDescription)"
        }
    }

    private func startModWatchersIfNeeded(globalRootPath: String, projectRootPath: String?) {
        if globalModsWatcher == nil {
            let watcher = DirectoryWatcher(path: globalRootPath) { [weak self] in
                Task { @MainActor in
                    self?.scheduleModsRefresh()
                }
            }
            do {
                try watcher.start()
                globalModsWatcher = watcher
            } catch {
                appendLog(.warning, "Failed to start global mods watcher: \(error.localizedDescription)")
            }
        }

        if watchedProjectModsRootPath != projectRootPath {
            projectModsWatcher?.stop()
            projectModsWatcher = nil
            watchedProjectModsRootPath = projectRootPath

            guard let projectRootPath else { return }
            let watcher = DirectoryWatcher(path: projectRootPath) { [weak self] in
                Task { @MainActor in
                    self?.scheduleModsRefresh()
                }
            }
            do {
                try watcher.start()
                projectModsWatcher = watcher
            } catch {
                appendLog(.warning, "Failed to start project mods watcher: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleModsRefresh() {
        modsDebounceTask?.cancel()
        modsDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                if Task.isCancelled { return }
                refreshModsSurface()
            } catch {
                return
            }
        }
    }

    private static func globalModsRootPath(fileManager: FileManager = .default) throws -> String {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base
            .appendingPathComponent("CodexChat", isDirectory: true)
            .appendingPathComponent("Mods", isDirectory: true)
            .appendingPathComponent("Global", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root.path
    }

    private static func projectModsRootPath(projectPath: String) -> String {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("mods", isDirectory: true)
            .standardizedFileURL
            .path
    }

    private static func normalizedOptionalPath(_ path: String?) -> String? {
        let trimmed = (path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
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

    private func restartRuntimeSession() async {
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
            if var context = activeTurnContext {
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

    private func refreshAccountState() async throws {
        guard let runtime else {
            accountState = .signedOut
            return
        }

        accountState = try await runtime.readAccount()
    }

    private func upsertProjectAPIKeyReferenceIfNeeded() async throws {
        guard let projectID = selectedProjectID,
              let projectSecretRepository
        else {
            return
        }

        _ = try await projectSecretRepository.upsertSecret(
            projectID: projectID,
            name: "OPENAI_API_KEY",
            keychainAccount: APIKeychainStore.runtimeAPIKeyAccount
        )
    }

    private func setSelectedProjectTrustState(_ trustState: ProjectTrustState) {
        guard let selectedProjectID,
              let projectRepository
        else {
            return
        }

        Task {
            do {
                _ = try await projectRepository.updateProjectTrustState(id: selectedProjectID, trustState: trustState)
                try await refreshProjects()
                projectStatusMessage = trustState == .trusted
                    ? "Project trusted. Runtime can act with normal settings."
                    : "Project marked untrusted. Read-only is recommended."
            } catch {
                projectStatusMessage = "Failed to update trust state: \(error.localizedDescription)"
                appendLog(.error, "Failed to update trust state: \(error.localizedDescription)")
            }
        }
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
               guard case let .message(message) = $0 else {
                   return false
               }
               return message.id == messageID
           }),
           case var .message(existingMessage) = entries[index]
        {
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

        for thread in loadedThreads {
            try await chatSearchRepository?.indexThreadTitle(
                threadID: thread.id,
                projectID: selectedProjectID,
                title: thread.title
            )
        }

        if let selectedThreadID,
           loadedThreads.contains(where: { $0.id == selectedThreadID })
        {
            return
        }

        selectedThreadID = loadedThreads.first?.id
    }

    private func refreshSkills() async throws {
        skillsState = .loading

        let discovered = try skillCatalogService.discoverSkills(projectPath: selectedProject?.path)
        let enabledPaths: Set<String> = if let selectedProjectID,
                                           let projectSkillEnablementRepository
        {
            try await projectSkillEnablementRepository.enabledSkillPaths(projectID: selectedProjectID)
        } else {
            []
        }

        let items = discovered.map { skill in
            SkillListItem(skill: skill, isEnabledForProject: enabledPaths.contains(skill.skillPath))
        }

        skillsState = .loaded(items)

        if let selectedSkillIDForComposer,
           !items.contains(where: { $0.id == selectedSkillIDForComposer && $0.isEnabledForProject })
        {
            self.selectedSkillIDForComposer = nil
        }
    }

    private func restoreLastOpenedContext() async throws {
        guard let preferenceRepository else { return }

        if let projectIDString = try await preferenceRepository.getPreference(key: .lastOpenedProjectID),
           let projectID = UUID(uuidString: projectIDString)
        {
            selectedProjectID = projectID
        }

        if let threadIDString = try await preferenceRepository.getPreference(key: .lastOpenedThreadID),
           let threadID = UUID(uuidString: threadIDString)
        {
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

    private func prepareProjectFolderStructure(projectPath: String) async throws {
        let fileManager = FileManager.default
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)

        // Human-owned project artifacts.
        try fileManager.createDirectory(
            at: projectURL.appendingPathComponent("chats", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: projectURL.appendingPathComponent("artifacts", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: projectURL.appendingPathComponent("mods", isDirectory: true),
            withIntermediateDirectories: true
        )

        // Project-scoped skills live under .agents/skills (managed by the app, not the agent).
        try fileManager.createDirectory(
            at: projectURL.appendingPathComponent(".agents/skills", isDirectory: true),
            withIntermediateDirectories: true
        )

        let memoryStore = ProjectMemoryStore(projectPath: projectPath)
        try await memoryStore.ensureStructure()
    }

    private func ensureSelectedProjectHasDefaultThread() async throws {
        guard let selectedProjectID,
              let threadRepository
        else {
            return
        }

        let threads = try await threadRepository.listThreads(projectID: selectedProjectID)
        if !threads.isEmpty {
            return
        }

        let title = "New chat"
        let thread = try await threadRepository.createThread(projectID: selectedProjectID, title: title)

        try await chatSearchRepository?.indexThreadTitle(
            threadID: thread.id,
            projectID: selectedProjectID,
            title: title
        )

        try await refreshThreads()
        selectedThreadID = thread.id
        try await persistSelection()
        refreshConversationState()
        appendLog(.info, "Created default thread for project \(selectedProjectID.uuidString)")
    }

    private func refreshConversationState() {
        guard let selectedThreadID else {
            conversationState = .idle
            return
        }

        let entries = transcriptStore[selectedThreadID, default: []]
        conversationState = .loaded(entries)
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

    private func handleRuntimeError(_ error: Error) {
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

    func approvalDangerWarning(for request: RuntimeApprovalRequest) -> String? {
        guard isPotentiallyRiskyApproval(request) else {
            return nil
        }
        return "This action appears risky. Review command/file details carefully before approving."
    }

    private func runtimeSafetyConfiguration(for project: ProjectRecord) -> RuntimeSafetyConfiguration {
        RuntimeSafetyConfiguration(
            sandboxMode: mapSandboxMode(project.sandboxMode),
            approvalPolicy: mapApprovalPolicy(project.approvalPolicy),
            networkAccess: project.networkAccess,
            webSearch: mapWebSearchMode(project.webSearch),
            writableRoots: [project.path]
        )
    }

    private func mapSandboxMode(_ mode: ProjectSandboxMode) -> RuntimeSandboxMode {
        switch mode {
        case .readOnly:
            .readOnly
        case .workspaceWrite:
            .workspaceWrite
        case .dangerFullAccess:
            .dangerFullAccess
        }
    }

    private func mapSkillScope(_ scope: SkillInstallScope) -> SkillScope {
        switch scope {
        case .project:
            .project
        case .global:
            .global
        }
    }

    private func mapApprovalPolicy(_ policy: ProjectApprovalPolicy) -> RuntimeApprovalPolicy {
        switch policy {
        case .untrusted:
            .untrusted
        case .onRequest:
            .onRequest
        case .never:
            .never
        }
    }

    private func mapWebSearchMode(_ mode: ProjectWebSearchMode) -> RuntimeWebSearchMode {
        switch mode {
        case .cached:
            .cached
        case .live:
            .live
        case .disabled:
            .disabled
        }
    }

    private func approvalSummary(for request: RuntimeApprovalRequest) -> String {
        var lines: [String] = []
        if let reason = request.reason, !reason.isEmpty {
            lines.append("reason: \(reason)")
        }
        if let risk = request.risk, !risk.isEmpty {
            lines.append("risk: \(risk)")
        }
        if let cwd = request.cwd, !cwd.isEmpty {
            lines.append("cwd: \(cwd)")
        }
        if !request.command.isEmpty {
            lines.append("command: \(request.command.joined(separator: " "))")
        }
        if !request.changes.isEmpty {
            lines.append("changes: \(request.changes.count) file(s)")
        }
        if lines.isEmpty {
            lines.append(request.detail)
        }
        return lines.joined(separator: "\n")
    }

    private func approvalDecisionLabel(_ decision: RuntimeApprovalDecision) -> String {
        switch decision {
        case .approveOnce:
            "Approve once"
        case .approveForSession:
            "Approve for session"
        case .decline:
            "Decline"
        case .cancel:
            "Cancel"
        }
    }

    private func isPotentiallyRiskyApproval(_ request: RuntimeApprovalRequest) -> Bool {
        let commandText = request.command.joined(separator: " ").lowercased()
        let riskyPatterns = [
            "rm -rf",
            "sudo ",
            "chmod ",
            "chown ",
            "mkfs",
            "dd ",
            "git reset --hard",
        ]

        if riskyPatterns.contains(where: { commandText.contains($0) }) {
            return true
        }

        if request.kind == .fileChange {
            return request.changes.contains(where: {
                $0.path.contains(".git/") || $0.path.contains(".codex/")
            })
        }

        return false
    }

    private func appendThreadLog(level: LogLevel, text: String, to threadID: UUID) {
        let sanitized = redactSensitiveText(in: text)
        var logs = threadLogsByThreadID[threadID, default: []]
        logs.append(ThreadLogEntry(level: level, text: sanitized))
        if logs.count > 1000 {
            logs.removeFirst(logs.count - 1000)
        }
        threadLogsByThreadID[threadID] = logs
    }

    private func restorePathsWithGit(_ paths: [String], projectPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", projectPath, "restore", "--"] + paths

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(bytes: errorData, encoding: .utf8) ?? ""
            throw NSError(
                domain: "CodexChatApp.GitRestore",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorText.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
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
            "(?i)authorization\\s*:\\s*bearer\\s+[^\\s]+",
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

    private static func isGitProject(path: String) -> Bool {
        let gitDirectory = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent(".git", isDirectory: true)
            .path
        return FileManager.default.fileExists(atPath: gitDirectory)
    }
}
