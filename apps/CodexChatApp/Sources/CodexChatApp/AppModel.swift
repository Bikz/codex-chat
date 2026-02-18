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
    enum DetailDestination: Equatable {
        case thread
        case skillsAndMods
        case none
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

    enum ReasoningLevel: String, CaseIterable, Codable, Sendable {
        case low
        case medium
        case high

        var title: String {
            switch self {
            case .low:
                "Low"
            case .medium:
                "Medium"
            case .high:
                "High"
            }
        }
    }

    enum ExperimentalFlag: String, CaseIterable, Codable, Sendable, Hashable {
        case parallelToolCalls
        case strictToolSchema
        case streamToolEvents

        var title: String {
            switch self {
            case .parallelToolCalls:
                "Parallel Tool Calls"
            case .strictToolSchema:
                "Strict Tool Schema"
            case .streamToolEvents:
                "Stream Tool Events"
            }
        }
    }

    struct ActiveTurnContext {
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
    @Published var generalThreadsState: SurfaceState<[ThreadRecord]> = .idle
    @Published var archivedThreadsState: SurfaceState<[ThreadRecord]> = .idle
    @Published var conversationState: SurfaceState<[TranscriptEntry]> = .idle
    @Published var searchState: SurfaceState<[ChatSearchResult]> = .idle
    @Published var skillsState: SurfaceState<[SkillListItem]> = .idle
    @Published var modsState: SurfaceState<ModsSurfaceModel> = .idle

    @Published var selectedProjectID: UUID?
    @Published var selectedThreadID: UUID?
    @Published var detailDestination: DetailDestination = .none
    @Published var expandedProjectIDs: Set<UUID> = []
    @Published var showAllProjects: Bool = false
    @Published var composerText = ""
    @Published var searchQuery = ""
    @Published var selectedSkillIDForComposer: String?
    @Published var defaultModel = "gpt-5-codex"
    @Published var defaultReasoning: ReasoningLevel = .medium
    @Published var defaultWebSearch: ProjectWebSearchMode = .cached
    @Published var defaultSafetySettings = ProjectSafetySettings(
        sandboxMode: .readOnly,
        approvalPolicy: .untrusted,
        networkAccess: false,
        webSearch: .cached
    )
    @Published var experimentalFlags: Set<ExperimentalFlag> = []

    @Published var isDiagnosticsVisible = false
    @Published var isProjectSettingsVisible = false
    @Published var isNewProjectSheetVisible = false
    @Published var isShellWorkspaceVisible = false
    @Published var isReviewChangesVisible = false
    @Published var runtimeStatus: RuntimeStatus = .idle
    @Published var runtimeIssue: RuntimeIssue?
    @Published var runtimeSetupMessage: String?
    @Published var accountState: RuntimeAccountState = .signedOut
    @Published var accountStatusMessage: String?
    @Published var approvalStatusMessage: String?
    @Published var projectStatusMessage: String?
    @Published var skillStatusMessage: String?
    @Published var memoryStatusMessage: String?
    @Published var modStatusMessage: String?
    @Published var storageStatusMessage: String?
    @Published var runtimeDefaultsStatusMessage: String?
    @Published var storageRootPath: String
    @Published var isAccountOperationInProgress = false
    @Published var isApprovalDecisionInProgress = false
    @Published var isSkillOperationInProgress = false
    @Published var isAPIKeyPromptVisible = false
    @Published var pendingAPIKey = ""
    @Published var activeApprovalRequest: RuntimeApprovalRequest?
    @Published var pendingModReview: PendingModReview?
    @Published var isModReviewDecisionInProgress = false
    @Published var isTurnInProgress = false
    @Published var logs: [LogEntry] = []
    @Published var threadLogsByThreadID: [UUID: [ThreadLogEntry]] = [:]
    @Published var reviewChangesByThreadID: [UUID: [RuntimeFileChange]] = [:]
    @Published var followUpQueueByThreadID: [UUID: [FollowUpQueueItemRecord]] = [:]
    @Published var followUpStatusMessage: String?
    @Published var runtimeCapabilities: RuntimeCapabilities = .none
    @Published var isNodeSkillInstallerAvailable = false
    @Published var shellWorkspacesByProjectID: [UUID: ProjectShellWorkspaceState] = [:]
    @Published var activeUntrustedShellWarning: UntrustedShellWarningContext?

    @Published var effectiveThemeOverride: ModThemeOverride = .init()
    @Published var effectiveDarkThemeOverride: ModThemeOverride = .init()

    let projectRepository: (any ProjectRepository)?
    let threadRepository: (any ThreadRepository)?
    let preferenceRepository: (any PreferenceRepository)?
    let runtimeThreadMappingRepository: (any RuntimeThreadMappingRepository)?
    let followUpQueueRepository: (any FollowUpQueueRepository)?
    let projectSecretRepository: (any ProjectSecretRepository)?
    let projectSkillEnablementRepository: (any ProjectSkillEnablementRepository)?
    let chatSearchRepository: (any ChatSearchRepository)?
    let runtime: CodexRuntime?
    let skillCatalogService: SkillCatalogService
    let modDiscoveryService: UIModDiscoveryService
    let keychainStore: APIKeychainStore
    let storagePaths: CodexChatStoragePaths

    var transcriptStore: [UUID: [TranscriptEntry]] = [:]
    var assistantMessageIDsByItemID: [UUID: [String: UUID]] = [:]
    var runtimeThreadIDByLocalThreadID: [UUID: String] = [:]
    var localThreadIDByRuntimeThreadID: [String: UUID] = [:]
    var localThreadIDByCommandItemID: [String: UUID] = [:]
    var approvalStateMachine = ApprovalStateMachine()
    var activeTurnContext: ActiveTurnContext?
    var activeModSnapshot: ModEditSafety.Snapshot?
    var runtimeEventTask: Task<Void, Never>?
    var runtimeAutoRecoveryTask: Task<Void, Never>?
    var chatGPTLoginPollingTask: Task<Void, Never>?
    var pendingChatGPTLoginID: String?
    var searchTask: Task<Void, Never>?
    var followUpDrainTask: Task<Void, Never>?
    var modsRefreshTask: Task<Void, Never>?
    var modsDebounceTask: Task<Void, Never>?
    var autoDrainPreferredThreadID: UUID?

    var globalModsWatcher: DirectoryWatcher?
    var projectModsWatcher: DirectoryWatcher?
    var watchedProjectModsRootPath: String?
    var untrustedShellAcknowledgedProjectIDs: Set<UUID> = []
    var didLoadUntrustedShellAcknowledgements = false

    init(
        repositories: MetadataRepositories?,
        runtime: CodexRuntime?,
        bootError: String?,
        skillCatalogService: SkillCatalogService = SkillCatalogService(),
        modDiscoveryService: UIModDiscoveryService = UIModDiscoveryService(),
        storagePaths: CodexChatStoragePaths = .current()
    ) {
        projectRepository = repositories?.projectRepository
        threadRepository = repositories?.threadRepository
        preferenceRepository = repositories?.preferenceRepository
        runtimeThreadMappingRepository = repositories?.runtimeThreadMappingRepository
        followUpQueueRepository = repositories?.followUpQueueRepository
        projectSecretRepository = repositories?.projectSecretRepository
        projectSkillEnablementRepository = repositories?.projectSkillEnablementRepository
        chatSearchRepository = repositories?.chatSearchRepository
        self.runtime = runtime
        self.skillCatalogService = skillCatalogService
        self.modDiscoveryService = modDiscoveryService
        self.storagePaths = storagePaths
        storageRootPath = storagePaths.rootURL.path
        keychainStore = APIKeychainStore()
        isNodeSkillInstallerAvailable = skillCatalogService.isNodeInstallerAvailable()

        if let bootError {
            projectsState = .failed(bootError)
            threadsState = .failed(bootError)
            archivedThreadsState = .failed(bootError)
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
        if let runtime, let loginID = pendingChatGPTLoginID {
            Task.detached {
                try? await runtime.cancelChatGPTLogin(loginID: loginID)
            }
        }

        runtimeEventTask?.cancel()
        runtimeAutoRecoveryTask?.cancel()
        chatGPTLoginPollingTask?.cancel()
        searchTask?.cancel()
        followUpDrainTask?.cancel()
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

    var generalProject: ProjectRecord? {
        projects.first(where: \.isGeneralProject)
    }

    var namedProjects: [ProjectRecord] {
        projects.filter { !$0.isGeneralProject }
    }

    var threads: [ThreadRecord] {
        if case let .loaded(threads) = threadsState {
            return threads
        }
        return []
    }

    var generalThreads: [ThreadRecord] {
        if case let .loaded(threads) = generalThreadsState {
            return threads
        }
        return []
    }

    var archivedThreads: [ThreadRecord] {
        if case let .loaded(threads) = archivedThreadsState {
            return threads
        }
        return []
    }

    var accountDisplayName: String {
        if let name = accountState.account?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty
        {
            return name
        }
        if let email = accountState.account?.email, !email.isEmpty {
            return email
        }
        return "Account"
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

    var canSubmitComposer: Bool {
        selectedThreadID != nil
            && selectedProjectID != nil
            && runtime != nil
            && runtimeIssue == nil
            && runtimeStatus == .connected
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

    var selectedFollowUpQueueItems: [FollowUpQueueItemRecord] {
        guard let selectedThreadID else { return [] }
        return followUpQueueByThreadID[selectedThreadID, default: []]
    }

    var canReviewChanges: Bool {
        !selectedThreadChanges.isEmpty
    }

    func refreshAccountState(refreshToken: Bool = false) async throws {
        guard let runtime else {
            accountState = .signedOut
            return
        }

        accountState = try await runtime.readAccount(refreshToken: refreshToken)
    }

    func upsertProjectAPIKeyReferenceIfNeeded() async throws {
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

    func appendEntry(_ entry: TranscriptEntry, to threadID: UUID) {
        transcriptStore[threadID, default: []].append(entry)
        refreshConversationState()
    }

    func appendAssistantDelta(_ delta: String, itemID: String, to threadID: UUID) {
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

    func refreshProjects() async throws {
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

    func refreshThreads() async throws {
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
            try await refreshFollowUpQueue(threadID: selectedThreadID)
            return
        }

        selectedThreadID = loadedThreads.first?.id
        if let selectedThreadID {
            try await refreshFollowUpQueue(threadID: selectedThreadID)
        }
    }

    func refreshSkills() async throws {
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

    func restoreLastOpenedContext() async throws {
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

    func persistSelection() async throws {
        guard let preferenceRepository else { return }

        let projectValue = selectedProjectID?.uuidString ?? ""
        let threadValue = selectedThreadID?.uuidString ?? ""
        try await preferenceRepository.setPreference(key: .lastOpenedProjectID, value: projectValue)
        try await preferenceRepository.setPreference(key: .lastOpenedThreadID, value: threadValue)
    }

    func refreshConversationState() {
        guard let selectedThreadID else {
            conversationState = .idle
            return
        }

        let entries = transcriptStore[selectedThreadID, default: []]
        conversationState = .loaded(entries)
    }
}
