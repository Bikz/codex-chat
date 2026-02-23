import AppKit
import CodexChatCore
import CodexChatInfra
import CodexComputerActions
import CodexExtensions
import CodexKit
import CodexMemory
import CodexMods
import CodexSkills
import Darwin
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum DetailDestination: Equatable {
        case thread
        case skillsAndMods
        case none
    }

    enum OnboardingMode: Equatable {
        case active
        case inactive
    }

    enum OnboardingReason: Equatable {
        case startup
        case signedOut
    }

    static var defaultMaxConcurrentTurns: Int {
        if let configured = ProcessInfo.processInfo.environment["CODEXCHAT_MAX_PARALLEL_TURNS"],
           let parsed = Int(configured),
           parsed > 0
        {
            return parsed
        }

        // Apple Silicon machines can handle many simultaneous sessions. Keep this high
        // enough for 50-thread workloads on baseline hardware, while still capping runaway
        // workloads behind a hard ceiling.
        return max(32, min(128, ProcessInfo.processInfo.activeProcessorCount * 8))
    }

    static var defaultRuntimePoolSize: Int {
        if let configured = ProcessInfo.processInfo.environment["CODEXCHAT_RUNTIME_POOL_SIZE"],
           let parsed = Int(configured),
           parsed > 0
        {
            // Runtime sharding is required for launch builds. Clamp to a multi-worker minimum.
            return max(2, min(parsed, 16))
        }

        let performanceCoreCount = appleSiliconPerformanceCoreCount()
        if performanceCoreCount > 0 {
            // Keep a conservative ceiling so the app remains responsive under mixed UI/runtime load.
            return max(2, min(performanceCoreCount, 6))
        }

        // Fallback when performance core topology is unavailable.
        return max(2, min(ProcessInfo.processInfo.activeProcessorCount / 2, 4))
    }

    static var activeRuntimePoolSize: Int {
        // Sharding is always enabled in launch mode.
        max(2, defaultRuntimePoolSize)
    }

    static var runtimeEventTraceSampleRate: Int {
        if let configured = ProcessInfo.processInfo.environment["CODEXCHAT_RUNTIME_EVENT_TRACE_SAMPLE_RATE"],
           let parsed = Int(configured),
           parsed > 0
        {
            return min(parsed, 512)
        }

        return 16
    }

    private static func appleSiliconPerformanceCoreCount() -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.perflevel0.physicalcpu", &value, &size, nil, 0)
        guard result == 0 else {
            return 0
        }
        return max(0, Int(value))
    }

    struct SkillListItem: Identifiable, Hashable {
        let skill: DiscoveredSkill
        var enabledTargets: Set<SkillEnablementTarget>
        var isEnabledForSelectedProject: Bool
        var updateCapability: SkillUpdateCapability
        var updateSource: String?
        var updateInstaller: SkillInstallerKind?

        var id: String {
            skill.id
        }

        var isEnabledGlobally: Bool {
            enabledTargets.contains(.global)
        }

        var isEnabledForGeneral: Bool {
            enabledTargets.contains(.general)
        }

        var isEnabledForProjectTarget: Bool {
            enabledTargets.contains(.project)
        }

        var isEnabledForProject: Bool {
            isEnabledForSelectedProject
        }
    }

    struct ModsSurfaceModel: Hashable {
        var globalMods: [DiscoveredUIMod]
        var projectMods: [DiscoveredUIMod]
        var selectedGlobalModPath: String?
        var selectedProjectModPath: String?
    }

    struct UserThemeCustomization: Hashable, Codable, Sendable {
        enum TransparencyMode: String, CaseIterable, Hashable, Codable, Sendable {
            case solid
            case glass
        }

        var isEnabled: Bool
        var accentHex: String?
        var sidebarHex: String?
        var backgroundHex: String?
        var panelHex: String?
        var sidebarGradientHex: String?
        var chatGradientHex: String?
        var gradientStrength: Double
        var transparencyMode: TransparencyMode

        private enum CodingKeys: String, CodingKey {
            case isEnabled
            case accentHex
            case sidebarHex
            case backgroundHex
            case panelHex
            case sidebarGradientHex
            case chatGradientHex
            case gradientStrength
            case transparencyMode
        }

        init(
            isEnabled: Bool = false,
            accentHex: String? = nil,
            sidebarHex: String? = nil,
            backgroundHex: String? = nil,
            panelHex: String? = nil,
            sidebarGradientHex: String? = nil,
            chatGradientHex: String? = nil,
            gradientStrength: Double = 0,
            transparencyMode: TransparencyMode = .solid
        ) {
            self.isEnabled = isEnabled
            self.accentHex = accentHex
            self.sidebarHex = sidebarHex
            self.backgroundHex = backgroundHex
            self.panelHex = panelHex
            self.sidebarGradientHex = sidebarGradientHex
            self.chatGradientHex = chatGradientHex
            self.gradientStrength = Self.clampedGradientStrength(gradientStrength)
            self.transparencyMode = transparencyMode
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
            let accentHex = try container.decodeIfPresent(String.self, forKey: .accentHex)
            let sidebarHex = try container.decodeIfPresent(String.self, forKey: .sidebarHex)
            let backgroundHex = try container.decodeIfPresent(String.self, forKey: .backgroundHex)
            let panelHex = try container.decodeIfPresent(String.self, forKey: .panelHex)
            let sidebarGradientHex = try container.decodeIfPresent(String.self, forKey: .sidebarGradientHex)
            let chatGradientHex = try container.decodeIfPresent(String.self, forKey: .chatGradientHex)
            let gradientStrength = try container.decodeIfPresent(Double.self, forKey: .gradientStrength) ?? 0
            let transparencyMode = try container.decodeIfPresent(TransparencyMode.self, forKey: .transparencyMode) ?? .solid

            self.init(
                isEnabled: isEnabled,
                accentHex: accentHex,
                sidebarHex: sidebarHex,
                backgroundHex: backgroundHex,
                panelHex: panelHex,
                sidebarGradientHex: sidebarGradientHex,
                chatGradientHex: chatGradientHex,
                gradientStrength: gradientStrength,
                transparencyMode: transparencyMode
            )
        }

        static func clampedGradientStrength(_ value: Double) -> Double {
            min(max(value, 0), 1)
        }

        var lightOverride: ModThemeOverride {
            guard isEnabled else { return .init() }
            return ModThemeOverride(
                palette: .init(
                    accentHex: accentHex,
                    backgroundHex: backgroundHex,
                    panelHex: panelHex,
                    sidebarHex: sidebarHex
                )
            )
        }

        var darkOverride: ModThemeOverride {
            lightOverride
        }

        var isGlassEnabled: Bool {
            isEnabled && transparencyMode == .glass
        }

        static let `default` = UserThemeCustomization()

        static let navyPastel = UserThemeCustomization(
            isEnabled: true,
            accentHex: "#7FA7CC",
            sidebarHex: "#111B2B",
            backgroundHex: "#0F1725",
            panelHex: "#152238",
            sidebarGradientHex: "#4E6883",
            chatGradientHex: "#6A7F9B",
            gradientStrength: 0.55,
            transparencyMode: .solid
        )
    }

    struct PromptBookEntry: Identifiable, Hashable, Sendable {
        var id: String
        var title: String
        var text: String
    }

    struct ModsBarQuickSwitchOption: Identifiable, Hashable, Sendable {
        enum Scope: String, Hashable, Sendable {
            case global
            case project

            var label: String {
                switch self {
                case .global:
                    "Global"
                case .project:
                    "Project"
                }
            }
        }

        var id: String {
            "\(scope.rawValue):\(mod.directoryPath)"
        }

        let scope: Scope
        let mod: DiscoveredUIMod
        let isSelected: Bool
    }

    struct PendingModReview: Identifiable, Hashable {
        let id: UUID
        let threadID: UUID
        let changes: [RuntimeFileChange]
        let reason: String
        let canRevert: Bool
    }

    struct ExtensionModsBarState: Hashable {
        let title: String?
        let markdown: String
        let scope: ExtensionModsBarOutput.Scope
        let actions: [ExtensionModsBarOutput.Action]
        let updatedAt: Date
    }

    struct ResolvedExtensionHook: Hashable {
        let modID: String
        let modDirectoryPath: String
        let definition: ModHookDefinition
    }

    struct ResolvedExtensionAutomation: Hashable {
        let modID: String
        let modDirectoryPath: String
        let definition: ModAutomationDefinition
    }

    struct ExtensionAutomationHealthSummary: Hashable, Sendable {
        let modID: String
        let automationCount: Int
        let failingAutomationCount: Int
        let nextRunAt: Date?
        let lastRunAt: Date?
        let lastStatus: String
        let lastError: String?

        var hasFailures: Bool {
            failingAutomationCount > 0
        }
    }

    struct PendingComputerActionPreview: Identifiable, Hashable {
        let id: String
        let threadID: UUID
        let projectID: UUID
        let request: ComputerActionRequest
        let artifact: ComputerActionPreviewArtifact
        let providerActionID: String
        let providerDisplayName: String
        let safetyLevel: ComputerActionSafetyLevel
        let requiresConfirmation: Bool

        init(
            threadID: UUID,
            projectID: UUID,
            request: ComputerActionRequest,
            artifact: ComputerActionPreviewArtifact,
            providerActionID: String,
            providerDisplayName: String,
            safetyLevel: ComputerActionSafetyLevel,
            requiresConfirmation: Bool
        ) {
            id = artifact.id
            self.threadID = threadID
            self.projectID = projectID
            self.request = request
            self.artifact = artifact
            self.providerActionID = providerActionID
            self.providerDisplayName = providerDisplayName
            self.safetyLevel = safetyLevel
            self.requiresConfirmation = requiresConfirmation
        }
    }

    struct PermissionRecoveryNotice: Identifiable, Equatable {
        let id: UUID
        let actionID: String
        let threadID: UUID?
        let target: PermissionRecoveryTarget
        let title: String
        let message: String
        let remediationSteps: [String]

        init(
            id: UUID = UUID(),
            actionID: String,
            threadID: UUID? = nil,
            target: PermissionRecoveryTarget,
            title: String,
            message: String,
            remediationSteps: [String]
        ) {
            self.id = id
            self.actionID = actionID
            self.threadID = threadID
            self.target = target
            self.title = title
            self.message = message
            self.remediationSteps = remediationSteps
        }
    }

    enum UserApprovalRequest: Identifiable, Equatable {
        case runtimeApproval(RuntimeApprovalRequest)
        case computerActionPreview(PendingComputerActionPreview)
        case permissionRecovery(PermissionRecoveryNotice)

        var id: String {
            switch self {
            case let .runtimeApproval(request):
                "runtime:\(request.id)"
            case let .computerActionPreview(preview):
                "computer:\(preview.id)"
            case let .permissionRecovery(notice):
                "permission:\(notice.id.uuidString)"
            }
        }
    }

    struct WorkerTraceEntry: Identifiable, Hashable {
        let id: String
        let threadID: UUID
        let turnID: String?
        let method: String
        let title: String
        let detail: String
        let trace: RuntimeAction.WorkerTrace
        let capturedAt: Date

        init(
            threadID: UUID,
            turnID: String?,
            method: String,
            title: String,
            detail: String,
            trace: RuntimeAction.WorkerTrace,
            capturedAt: Date = Date()
        ) {
            id = "\(threadID.uuidString):\(turnID ?? "unknown"): \(method):\(capturedAt.timeIntervalSince1970)"
            self.threadID = threadID
            self.turnID = turnID
            self.method = method
            self.title = title
            self.detail = detail
            self.trace = trace
            self.capturedAt = capturedAt
        }
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

    enum VoiceCaptureState: Equatable {
        case idle
        case requestingPermission
        case recording(startedAt: Date)
        case transcribing
        case failed(message: String)
    }

    enum ReasoningLevel: String, CaseIterable, Codable, Sendable {
        case none
        case minimal
        case low
        case medium
        case high
        case xhigh

        var title: String {
            switch self {
            case .none:
                "None"
            case .minimal:
                "Minimal"
            case .low:
                "Low"
            case .medium:
                "Medium"
            case .high:
                "High"
            case .xhigh:
                "X-High"
            }
        }
    }

    enum ComposerMemoryMode: String, CaseIterable, Codable, Sendable {
        case projectDefault = "project-default"
        case off
        case summariesOnly = "summaries-only"
        case summariesAndKeyFacts = "summaries-and-key-facts"

        var title: String {
            switch self {
            case .projectDefault:
                "Project default"
            case .off:
                "Off"
            case .summariesOnly:
                "Summary"
            case .summariesAndKeyFacts:
                "Key facts"
            }
        }
    }

    enum ComposerAttachmentKind: String, Codable, Hashable, Sendable {
        case localImage
        case mentionFile
    }

    struct ComposerAttachment: Identifiable, Hashable, Sendable {
        let id: UUID
        let path: String
        let name: String
        let kind: ComposerAttachmentKind

        init(
            id: UUID = UUID(),
            path: String,
            name: String,
            kind: ComposerAttachmentKind
        ) {
            self.id = id
            self.path = path
            self.name = name
            self.kind = kind
        }
    }

    struct ActiveTurnContext: Sendable {
        var localTurnID: UUID
        var localThreadID: UUID
        var projectID: UUID
        var projectPath: String
        var runtimeThreadID: String
        var runtimeTurnID: String?
        var memoryWriteMode: ProjectMemoryWriteMode
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
    @Published var availableSkillsCatalogState: SurfaceState<[CatalogSkillListing]> = .idle
    @Published var modsState: SurfaceState<ModsSurfaceModel> = .idle

    @Published var selectedProjectID: UUID?
    @Published var selectedThreadID: UUID? {
        didSet {
            clearUnreadMarker(for: selectedThreadID)
            syncApprovalPresentationState()
        }
    }

    @Published var draftChatProjectID: UUID?
    @Published var detailDestination: DetailDestination = .none
    @Published var onboardingMode: OnboardingMode = .inactive
    @Published var expandedProjectIDs: Set<UUID> = []
    @Published var showAllProjects: Bool = false
    @Published var composerText = ""
    @Published var composerMemoryMode: ComposerMemoryMode = .projectDefault
    @Published var composerAttachments: [ComposerAttachment] = []
    @Published var searchQuery = ""
    @Published var selectedSkillIDForComposer: String?
    @Published var skillEnablementTargetSelectionBySkillID: [String: SkillEnablementTarget] = [:]
    @Published var defaultModel = ""
    @Published var defaultReasoning: ReasoningLevel = .medium
    @Published var defaultWebSearch: ProjectWebSearchMode = .cached
    @Published var transcriptDetailLevel: TranscriptDetailLevel = .chat
    @Published var defaultSafetySettings = ProjectSafetySettings(
        sandboxMode: .readOnly,
        approvalPolicy: .untrusted,
        networkAccess: false,
        webSearch: .cached
    )
    @Published var codexConfigDocument: CodexConfigDocument = .empty()
    @Published var codexConfigSchema: CodexConfigSchemaNode = .object
    @Published var codexConfigSchemaSource: CodexConfigSchemaSource = .bundled
    @Published var codexConfigValidationIssues: [CodexConfigValidationIssue] = []
    @Published var codexConfigStatusMessage: String?
    @Published var isCodexConfigBusy = false

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
    @Published var extensionStatusMessage: String?
    @Published var storageStatusMessage: String?
    @Published var runtimeDefaultsStatusMessage: String?
    @Published var voiceCaptureState: VoiceCaptureState = .idle
    @Published var voiceCaptureElapsedText: String?
    @Published var storageRootPath: String
    @Published var isStorageRepairInProgress = false
    @Published var lastCodexHomeQuarantinePath: String?
    @Published var isAccountOperationInProgress = false
    @Published var isApprovalDecisionInProgress = false
    @Published var isSkillOperationInProgress = false
    @Published var isModOperationInProgress = false
    @Published var isAPIKeyPromptVisible = false
    @Published var pendingAPIKey = ""
    @Published var activeApprovalRequest: RuntimeApprovalRequest?
    @Published var unscopedApprovalRequests: [RuntimeApprovalRequest] = []
    @Published var pendingApprovalThreadIDs: Set<UUID> = []
    @Published var pendingModReview: PendingModReview?
    @Published var isModReviewDecisionInProgress = false
    @Published var isTurnInProgress = false
    @Published var activeTurnThreadIDs: Set<UUID> = []
    @Published var logs: [LogEntry] = []
    @Published var threadLogsByThreadID: [UUID: [ThreadLogEntry]] = [:]
    @Published var reviewChangesByThreadID: [UUID: [RuntimeFileChange]] = [:]
    @Published var followUpQueueByThreadID: [UUID: [FollowUpQueueItemRecord]] = [:]
    @Published var unreadThreadIDs: Set<UUID> = []
    @Published var followUpStatusMessage: String?
    @Published var runtimeCapabilities: RuntimeCapabilities = .none
    @Published var runtimePoolSnapshot: RuntimePoolSnapshot = .empty
    @Published var adaptiveTurnConcurrencyLimit: Int = AppModel.defaultMaxConcurrentTurns
    @Published var runtimeModelCatalog: [RuntimeModelInfo] = []
    @Published var isNodeSkillInstallerAvailable = false
    @Published var shellWorkspacesByProjectID: [UUID: ProjectShellWorkspaceState] = [:]
    @Published var activeUntrustedShellWarning: UntrustedShellWarningContext?
    @Published var extensionModsBarByThreadID: [UUID: ExtensionModsBarState] = [:]
    @Published var extensionGlobalModsBarState: ExtensionModsBarState?
    @Published var extensionModsBarVisibilityByThreadID: [UUID: Bool] = [:]
    @Published var extensionCatalogState: SurfaceState<[CatalogModListing]> = .idle
    @Published var extensionAutomationHealthByModID: [String: ExtensionAutomationHealthSummary] = [:]
    @Published var activeModsBarSlot: ModUISlots.ModsBar?
    @Published var activeModsBarModID: String?
    @Published var activeModsBarModDirectoryPath: String?
    @Published var pendingComputerActionPreview: PendingComputerActionPreview?
    @Published var isComputerActionExecutionInProgress = false
    @Published var computerActionStatusMessage: String?
    @Published var permissionRecoveryNotice: PermissionRecoveryNotice?
    @Published var workerTraceByThreadID: [UUID: [WorkerTraceEntry]] = [:]
    @Published var activeWorkerTraceEntry: WorkerTraceEntry?
    @Published var areAdvancedExecutableModsUnlocked = false
    @Published var userThemeCustomization: UserThemeCustomization = .default
    @Published var isPlanRunnerSheetVisible = false
    @Published var planRunnerSourcePath = ""
    @Published var planRunnerDraftText = ""
    @Published var planRunnerPreferredBatchSize = 4
    @Published var planRunnerStatusMessage: String?
    @Published var isPlanRunnerExecuting = false
    @Published var activePlanRun: PlanRunRecord?
    @Published var planRunnerTaskStates: [PlanRunTaskRecord] = []

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
    let extensionInstallRepository: (any ExtensionInstallRepository)?
    let extensionPermissionRepository: (any ExtensionPermissionRepository)?
    let extensionHookStateRepository: (any ExtensionHookStateRepository)?
    let extensionAutomationStateRepository: (any ExtensionAutomationStateRepository)?
    let computerActionPermissionRepository: (any ComputerActionPermissionRepository)?
    let computerActionRunRepository: (any ComputerActionRunRepository)?
    let planRunRepository: (any PlanRunRepository)?
    let planRunTaskRepository: (any PlanRunTaskRepository)?
    let runtime: CodexRuntime?
    let runtimePool: RuntimePool?
    let computerActionRegistry: ComputerActionRegistry
    let skillCatalogService: SkillCatalogService
    let skillCatalogProvider: any SkillCatalogProvider
    let modDiscoveryService: UIModDiscoveryService
    let modCatalogProvider: any ModCatalogProvider
    let keychainStore: APIKeychainStore
    let storagePaths: CodexChatStoragePaths
    let voiceCaptureService: any VoiceCaptureService
    let codexConfigFileStore: CodexConfigFileStore
    let codexConfigSchemaLoader: CodexConfigSchemaLoader
    let codexConfigValidator = CodexConfigValidator()
    let extensionWorkerRunner = ExtensionWorkerRunner()
    let extensionStateStore = ExtensionStateStore()
    let extensionEventBus = ExtensionEventBus()
    let runtimeThreadResolutionCoordinator = RuntimeThreadResolutionCoordinator()
    let turnConcurrencyScheduler = TurnConcurrencyScheduler(maxConcurrentTurns: AppModel.defaultMaxConcurrentTurns)
    let adaptiveConcurrencyController = AdaptiveConcurrencyController(hardMaximumLimit: AppModel.defaultMaxConcurrentTurns)
    lazy var turnPersistenceScheduler = TurnPersistenceScheduler(maxConcurrentJobs: 4) { [weak self] job in
        guard let self else { return }
        await persistCompletedTurn(context: job.context, completion: job.completion)
    }

    lazy var persistenceBatcher = PersistenceBatcher { [weak self] jobs in
        guard let self else { return }
        for job in jobs {
            await turnPersistenceScheduler.enqueue(
                context: job.context,
                completion: job.completion
            )
        }
    }

    lazy var runtimeEventDispatchBridge = RuntimeEventDispatchBridge { [weak self] events in
        self?.handleRuntimeEventBatch(events)
    }

    lazy var conversationUpdateScheduler = ConversationUpdateScheduler { [weak self] batch in
        self?.applyCoalescedAssistantDeltaBatch(batch)
    }

    var transcriptStore: [UUID: [TranscriptEntry]] = [:]
    var transcriptRevisionsByThreadID: [UUID: UInt64] = [:]
    var transcriptPresentationCache: [TranscriptPresentationCacheKey: TranscriptPresentationCacheEntry] = [:]
    var transcriptPresentationCacheLRU: [TranscriptPresentationCacheKey] = []
    var assistantMessageIDsByItemID: [UUID: [String: UUID]] = [:]
    var runtimeThreadIDByLocalThreadID: [UUID: String] = [:]
    var localThreadIDByRuntimeThreadID: [String: UUID] = [:]
    var localThreadIDByRuntimeTurnID: [String: UUID] = [:]
    var localThreadIDByCommandItemID: [String: UUID] = [:]
    var approvalStateMachine = ApprovalStateMachine()
    var approvalDecisionInFlightRequestIDs: Set<Int> = []
    var activeTurnContextsByThreadID: [UUID: ActiveTurnContext] = [:]
    var pendingTurnStartThreadIDs: Set<UUID> = []
    var activeModSnapshotByThreadID: [UUID: ModEditSafety.Snapshot] = [:]
    var runtimeEventTask: Task<Void, Never>?
    var runtimeAutoRecoveryTask: Task<Void, Never>?
    var onboardingCompletionTask: Task<Void, Never>?
    var chatGPTLoginPollingTask: Task<Void, Never>?
    var pendingChatGPTLoginID: String?
    var searchTask: Task<Void, Never>?
    var followUpDrainTask: Task<Void, Never>?
    var modsRefreshTask: Task<Void, Never>?
    var modsDebounceTask: Task<Void, Never>?
    var startupBackgroundTask: Task<Void, Never>?
    var startupLoadGeneration: UInt64 = 0
    var runtimeThreadPrewarmTask: Task<Void, Never>?
    var runtimeThreadPrewarmGeneration: UInt64 = 0
    var selectedThreadHydrationTask: Task<Void, Never>?
    var selectedThreadHydrationGeneration: UInt64 = 0
    var planRunnerTask: Task<Void, Never>?
    var workerTracePersistenceTask: Task<Void, Never>?
    var secondarySurfaceRefreshTask: Task<Void, Never>?
    var adaptiveConcurrencyRefreshTask: Task<Void, Never>?
    var runtimePoolMetricsTask: Task<Void, Never>?
    var autoDrainPreferredThreadID: UUID?
    var pendingFollowUpAutoDrainReason: String?
    var pendingFirstTurnTitleThreadIDs: Set<UUID> = []
    var voiceAutoStopTask: Task<Void, Never>?
    var voiceElapsedTickerTask: Task<Void, Never>?
    var userThemePersistenceTask: Task<Void, Never>?
    var voiceCaptureSessionID: UInt64 = 0
    var voiceAutoStopDurationNanoseconds: UInt64 = 90_000_000_000
    let voiceElapsedClock = ContinuousClock()
    var voiceCaptureRecordingStart: ContinuousClock.Instant?
    var activeExtensionHooks: [ResolvedExtensionHook] = []
    var activeExtensionAutomations: [ResolvedExtensionAutomation] = []
    var extensionHookDebounceTimestamps: [String: Date] = [:]
    var extensionAutomationScheduler = ExtensionAutomationScheduler()
    var runtimeRepairSuggestedThreadIDs: Set<UUID> = []
    var runtimeRepairPendingRuntimeThreadIDs: Set<String> = []
    var runtimeEventTraceSampleCounter: UInt64 = 0
    var workerTraceByActionFingerprint: [String: WorkerTraceEntry] = [:]
    var computerActionPermissionPromptHandler: ((String, ComputerActionSafetyLevel) -> Bool)?
    var computerActionHarnessEnvironment: ComputerActionHarnessEnvironment?
    var computerActionHarnessServer: ComputerActionHarnessServer?
    var harnessRunContextByToken: [String: HarnessRunContext] = [:]
    var globalModsWatcher: DirectoryWatcher?
    var projectModsWatcher: DirectoryWatcher?
    var watchedProjectModsRootPath: String?
    var untrustedShellAcknowledgedProjectIDs: Set<UUID> = []
    var didLoadUntrustedShellAcknowledgements = false
    var didPrepareForTeardown = false

    init(
        repositories: MetadataRepositories?,
        runtime: CodexRuntime?,
        bootError: String?,
        computerActionRegistry: ComputerActionRegistry = ComputerActionRegistry(),
        skillCatalogService: SkillCatalogService = SkillCatalogService(),
        skillCatalogProvider: any SkillCatalogProvider = EmptySkillCatalogProvider(),
        modDiscoveryService: UIModDiscoveryService = UIModDiscoveryService(),
        modCatalogProvider: any ModCatalogProvider = EmptyModCatalogProvider(),
        voiceCaptureService: (any VoiceCaptureService)? = nil,
        storagePaths: CodexChatStoragePaths = .current(),
        harnessEnvironment: ComputerActionHarnessEnvironment? = nil
    ) {
        projectRepository = repositories?.projectRepository
        threadRepository = repositories?.threadRepository
        preferenceRepository = repositories?.preferenceRepository
        runtimeThreadMappingRepository = repositories?.runtimeThreadMappingRepository
        followUpQueueRepository = repositories?.followUpQueueRepository
        projectSecretRepository = repositories?.projectSecretRepository
        projectSkillEnablementRepository = repositories?.projectSkillEnablementRepository
        chatSearchRepository = repositories?.chatSearchRepository
        extensionInstallRepository = repositories?.extensionInstallRepository
        extensionPermissionRepository = repositories?.extensionPermissionRepository
        extensionHookStateRepository = repositories?.extensionHookStateRepository
        extensionAutomationStateRepository = repositories?.extensionAutomationStateRepository
        computerActionPermissionRepository = repositories?.computerActionPermissionRepository
        computerActionRunRepository = repositories?.computerActionRunRepository
        planRunRepository = repositories?.planRunRepository
        planRunTaskRepository = repositories?.planRunTaskRepository
        self.runtime = runtime
        runtimePool = runtime.map { RuntimePool(primaryRuntime: $0, configuredWorkerCount: Self.activeRuntimePoolSize) }
        self.computerActionRegistry = computerActionRegistry
        self.skillCatalogService = skillCatalogService
        self.skillCatalogProvider = skillCatalogProvider
        self.modDiscoveryService = modDiscoveryService
        self.modCatalogProvider = modCatalogProvider
        self.storagePaths = storagePaths
        computerActionHarnessEnvironment = harnessEnvironment
        self.voiceCaptureService = voiceCaptureService ?? AppleSpeechVoiceCaptureService()
        storageRootPath = storagePaths.rootURL.path
        keychainStore = APIKeychainStore()
        isNodeSkillInstallerAvailable = skillCatalogService.isNodeInstallerAvailable()
        codexConfigFileStore = CodexConfigFileStore(fileURL: storagePaths.codexConfigURL)
        let bundledSchemaURL = Bundle.module.url(forResource: "codex-config-schema", withExtension: "json")
            ?? Bundle.module.url(
                forResource: "codex-config-schema",
                withExtension: "json",
                subdirectory: "Resources"
            )
        codexConfigSchemaLoader = CodexConfigSchemaLoader(
            cacheURL: storagePaths.systemURL.appendingPathComponent("codex-config-schema.json", isDirectory: false),
            bundledSchemaURL: bundledSchemaURL
        )

        if let bootError {
            projectsState = .failed(bootError)
            threadsState = .failed(bootError)
            archivedThreadsState = .failed(bootError)
            conversationState = .failed(bootError)
            skillsState = .failed(bootError)
            availableSkillsCatalogState = .failed(bootError)
            runtimeStatus = .error
            runtimeIssue = .recoverable(bootError)
            appendLog(.error, bootError)
        } else {
            appendLog(.info, "App model initialized")
        }
    }

    func prepareForTeardown() {
        guard !didPrepareForTeardown else {
            return
        }
        didPrepareForTeardown = true

        let runtimePoolForLoginCancellation = runtimePool
        let pendingLoginID = pendingChatGPTLoginID
        pendingChatGPTLoginID = nil

        runtimeEventTask?.cancel()
        runtimeAutoRecoveryTask?.cancel()
        onboardingCompletionTask?.cancel()
        chatGPTLoginPollingTask?.cancel()
        chatGPTLoginPollingTask = nil
        searchTask?.cancel()
        followUpDrainTask?.cancel()
        modsRefreshTask?.cancel()
        modsDebounceTask?.cancel()
        startupBackgroundTask?.cancel()
        runtimeThreadPrewarmGeneration = runtimeThreadPrewarmGeneration &+ 1
        runtimeThreadPrewarmTask?.cancel()
        runtimeThreadPrewarmTask = nil
        selectedThreadHydrationTask?.cancel()
        planRunnerTask?.cancel()
        workerTracePersistenceTask?.cancel()
        secondarySurfaceRefreshTask?.cancel()
        adaptiveConcurrencyRefreshTask?.cancel()
        stopRuntimePoolMetricsLoop()
        voiceAutoStopTask?.cancel()
        voiceElapsedTickerTask?.cancel()
        userThemePersistenceTask?.cancel()
        conversationUpdateScheduler.invalidate()
        globalModsWatcher?.stop()
        globalModsWatcher = nil
        projectModsWatcher?.stop()
        projectModsWatcher = nil
        computerActionHarnessServer?.stop()
        computerActionHarnessServer = nil
        harnessRunContextByToken.removeAll(keepingCapacity: false)

        if let runtimePoolForLoginCancellation, let pendingLoginID {
            Task {
                try? await runtimePoolForLoginCancellation.cancelChatGPTLogin(loginID: pendingLoginID)
            }
        }

        let threadResolutionCoordinator = runtimeThreadResolutionCoordinator
        let turnScheduler = turnConcurrencyScheduler
        let persistenceScheduler = turnPersistenceScheduler
        let persistenceBatcher = persistenceBatcher
        let eventBridge = runtimeEventDispatchBridge
        Task {
            await threadResolutionCoordinator.cancelAll()
            await persistenceBatcher.shutdown()
            await turnScheduler.cancelAll()
            await persistenceScheduler.cancelQueuedJobs()
            await eventBridge.stop()
        }

        if !activeExtensionAutomations.isEmpty {
            let scheduler = extensionAutomationScheduler
            Task {
                await scheduler.stopAll()
            }
        }
    }

    deinit {
        guard !didPrepareForTeardown else {
            return
        }

        let runtimePoolForLoginCancellation = runtimePool
        let pendingLoginID = pendingChatGPTLoginID

        runtimeEventTask?.cancel()
        runtimeAutoRecoveryTask?.cancel()
        onboardingCompletionTask?.cancel()
        chatGPTLoginPollingTask?.cancel()
        searchTask?.cancel()
        followUpDrainTask?.cancel()
        modsRefreshTask?.cancel()
        modsDebounceTask?.cancel()
        startupBackgroundTask?.cancel()
        runtimeThreadPrewarmGeneration = runtimeThreadPrewarmGeneration &+ 1
        runtimeThreadPrewarmTask?.cancel()
        runtimeThreadPrewarmTask = nil
        selectedThreadHydrationTask?.cancel()
        planRunnerTask?.cancel()
        workerTracePersistenceTask?.cancel()
        secondarySurfaceRefreshTask?.cancel()
        adaptiveConcurrencyRefreshTask?.cancel()
        runtimePoolMetricsTask?.cancel()
        voiceAutoStopTask?.cancel()
        voiceElapsedTickerTask?.cancel()
        userThemePersistenceTask?.cancel()
        globalModsWatcher?.stop()
        projectModsWatcher?.stop()
        computerActionHarnessServer?.stop()
        computerActionHarnessServer = nil

        if let runtimePoolForLoginCancellation, let pendingLoginID {
            Task {
                try? await runtimePoolForLoginCancellation.cancelChatGPTLogin(loginID: pendingLoginID)
            }
        }

        let threadResolutionCoordinator = runtimeThreadResolutionCoordinator
        let turnScheduler = turnConcurrencyScheduler
        Task {
            await threadResolutionCoordinator.cancelAll()
            await turnScheduler.cancelAll()
        }

        if !activeExtensionAutomations.isEmpty {
            let scheduler = extensionAutomationScheduler
            Task {
                await scheduler.stopAll()
            }
        }
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

    var pendingApprovalForSelectedThread: RuntimeApprovalRequest? {
        guard let selectedThreadID else {
            return nil
        }
        return approvalStateMachine.pendingRequest(for: selectedThreadID)
    }

    var pendingComputerActionPreviewForSelectedThread: PendingComputerActionPreview? {
        guard let selectedThreadID,
              let preview = pendingComputerActionPreview,
              preview.threadID == selectedThreadID
        else {
            return nil
        }
        return preview
    }

    var pendingPermissionRecoveryForSelectedThread: PermissionRecoveryNotice? {
        guard let selectedThreadID,
              let notice = permissionRecoveryNotice,
              notice.threadID == selectedThreadID
        else {
            return nil
        }
        return notice
    }

    var pendingUserApprovalForSelectedThread: UserApprovalRequest? {
        if let runtimeApproval = pendingApprovalForSelectedThread {
            return .runtimeApproval(runtimeApproval)
        }
        if let computerActionPreview = pendingComputerActionPreviewForSelectedThread {
            return .computerActionPreview(computerActionPreview)
        }
        if let permissionRecovery = pendingPermissionRecoveryForSelectedThread {
            return .permissionRecovery(permissionRecovery)
        }
        return nil
    }

    var hasPendingApprovalForSelectedThread: Bool {
        pendingUserApprovalForSelectedThread != nil
    }

    var isSelectedThreadApprovalInProgress: Bool {
        if let request = pendingApprovalForSelectedThread {
            return approvalDecisionInFlightRequestIDs.contains(request.id)
        }
        return isComputerActionExecutionInProgress
    }

    func hasPendingApproval(for threadID: UUID) -> Bool {
        if approvalStateMachine.pendingRequest(for: threadID) != nil {
            return true
        }
        if pendingComputerActionPreview?.threadID == threadID {
            return true
        }
        if permissionRecoveryNotice?.threadID == threadID {
            return true
        }
        return false
    }

    var canSendMessages: Bool {
        selectedThreadID != nil
            && runtimeIssue == nil
            && runtimeStatus == .connected
            && pendingModReview == nil
            && !hasPendingApprovalForSelectedThread
            && !isSelectedThreadApprovalInProgress
            && !isSelectedThreadWorking
            && isSignedInForRuntime
    }

    var canSubmitComposer: Bool {
        selectedProjectID != nil
            && (selectedThreadID != nil || hasActiveDraftChatForSelectedProject)
            && runtimePool != nil
            && runtimeIssue == nil
            && runtimeStatus == .connected
            && isSignedInForRuntime
    }

    var hasComposerDraftContent: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !composerAttachments.isEmpty
    }

    var canSubmitComposerInput: Bool {
        canSubmitComposer && hasComposerDraftContent
    }

    var hasActiveDraftChatForSelectedProject: Bool {
        guard let selectedProjectID else { return false }
        return selectedThreadID == nil && draftChatProjectID == selectedProjectID
    }

    var isSignedInForRuntime: Bool {
        !accountState.requiresOpenAIAuth || accountState.account != nil
    }

    var isOnboardingActive: Bool {
        onboardingMode == .active
    }

    var isOnboardingReadyToComplete: Bool {
        isSignedInForRuntime
            && runtimeStatus == .connected
            && runtimeIssue == nil
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
        skills.filter(\.isEnabledForSelectedProject)
    }

    var selectedSkillForComposer: SkillListItem? {
        guard let selectedSkillIDForComposer else { return nil }
        return skills.first(where: { $0.id == selectedSkillIDForComposer && $0.isEnabledForSelectedProject })
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

    var selectedExtensionModsBarState: ExtensionModsBarState? {
        guard let selectedThreadID else { return extensionGlobalModsBarState }
        return extensionModsBarByThreadID[selectedThreadID] ?? extensionGlobalModsBarState
    }

    var resolvedLightThemeOverride: ModThemeOverride {
        effectiveThemeOverride.merged(with: userThemeCustomization.lightOverride)
    }

    var resolvedDarkThemeOverride: ModThemeOverride {
        effectiveDarkThemeOverride.merged(with: userThemeCustomization.darkOverride)
    }

    var isTransparentThemeMode: Bool {
        userThemeCustomization.isGlassEnabled
    }

    var isModsBarVisibleForSelectedThread: Bool {
        guard let selectedThreadID else { return false }
        return extensionModsBarVisibilityByThreadID[selectedThreadID, default: false]
    }

    var canToggleModsBarForSelectedThread: Bool {
        selectedThreadID != nil
    }

    var isModsBarAvailableForSelectedThread: Bool {
        selectedThreadID != nil && (activeModsBarSlot?.enabled ?? false)
    }

    var canReviewChanges: Bool {
        !selectedThreadChanges.isEmpty
    }

    func refreshAccountState(refreshToken: Bool = false) async throws {
        guard let runtimePool else {
            accountState = .signedOut
            completeOnboardingIfReady()
            return
        }

        accountState = try await runtimePool.readAccount(refreshToken: refreshToken)
        completeOnboardingIfReady()
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
        bumpTranscriptRevision(for: threadID)
        refreshConversationStateIfSelectedThreadChanged(threadID)
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
            bumpTranscriptRevision(for: threadID)
            refreshConversationStateIfSelectedThreadChanged(threadID)
            return
        }

        let message = ChatMessage(threadId: threadID, role: .assistant, text: delta)
        entries.append(.message(message))
        itemMap[itemID] = message.id

        transcriptStore[threadID] = entries
        assistantMessageIDsByItemID[threadID] = itemMap
        bumpTranscriptRevision(for: threadID)
        refreshConversationStateIfSelectedThreadChanged(threadID)
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

    func refreshThreads(refreshSelectedThreadFollowUpQueue: Bool = true) async throws {
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
           loadedThreads.contains(where: { $0.id == selectedThreadID })
        {
            if refreshSelectedThreadFollowUpQueue {
                try await refreshFollowUpQueue(threadID: selectedThreadID)
            }
            return
        }

        if hasActiveDraftChatForSelectedProject {
            return
        }

        selectedThreadID = loadedThreads.first?.id
        if refreshSelectedThreadFollowUpQueue,
           let selectedThreadID
        {
            try await refreshFollowUpQueue(threadID: selectedThreadID)
        }
    }

    func refreshSkills() async throws {
        skillsState = .loading

        let discovered = try skillCatalogService.discoverSkills(projectPath: selectedProject?.path)
        let selectedProjectID = selectedProjectID
        let globalEnabledPaths: Set<String> = if let projectSkillEnablementRepository {
            try await projectSkillEnablementRepository.enabledSkillPaths(target: .global, projectID: nil)
        } else {
            []
        }
        let generalEnabledPaths: Set<String> = if let projectSkillEnablementRepository {
            try await projectSkillEnablementRepository.enabledSkillPaths(target: .general, projectID: nil)
        } else {
            []
        }
        let projectEnabledPaths: Set<String> = if let selectedProjectID,
                                                  let projectSkillEnablementRepository
        {
            try await projectSkillEnablementRepository.enabledSkillPaths(target: .project, projectID: selectedProjectID)
        } else {
            []
        }
        let resolvedEnabledPaths: Set<String> = if let projectSkillEnablementRepository {
            try await projectSkillEnablementRepository.resolvedEnabledSkillPaths(
                forProjectID: selectedProjectID,
                generalProjectID: generalProject?.id
            )
        } else {
            []
        }

        let items = discovered.map { skill in
            var enabledTargets = Set<SkillEnablementTarget>()
            if globalEnabledPaths.contains(skill.skillPath) {
                enabledTargets.insert(.global)
            }
            if generalEnabledPaths.contains(skill.skillPath) {
                enabledTargets.insert(.general)
            }
            if projectEnabledPaths.contains(skill.skillPath) {
                enabledTargets.insert(.project)
            }

            let updateCapability = skillCatalogService.updateCapability(for: skill)
            let mappedCapability: SkillUpdateCapability = switch updateCapability.kind {
            case .gitUpdate:
                .gitUpdate
            case .reinstall:
                .reinstall
            case .unavailable:
                .unavailable
            }

            return SkillListItem(
                skill: skill,
                enabledTargets: enabledTargets,
                isEnabledForSelectedProject: resolvedEnabledPaths.contains(skill.skillPath),
                updateCapability: mappedCapability,
                updateSource: updateCapability.source,
                updateInstaller: updateCapability.installer
            )
        }

        skillsState = .loaded(items)

        let activeSkillIDs = Set(items.map(\.id))
        skillEnablementTargetSelectionBySkillID = skillEnablementTargetSelectionBySkillID.filter { activeSkillIDs.contains($0.key) }
        for item in items where skillEnablementTargetSelectionBySkillID[item.id] == nil {
            skillEnablementTargetSelectionBySkillID[item.id] = selectedProjectID == nil ? .global : .project
        }

        if let selectedSkillIDForComposer,
           !items.contains(where: { $0.id == selectedSkillIDForComposer && $0.isEnabledForSelectedProject })
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
            conversationState = hasActiveDraftChatForSelectedProject ? .loaded([]) : .idle
            return
        }

        let entries = transcriptStore[selectedThreadID, default: []]
        conversationState = .loaded(entries)
    }

    func refreshConversationStateIfSelectedThreadChanged(_ changedThreadID: UUID?) {
        guard let selectedThreadID else {
            refreshConversationState()
            return
        }

        guard let changedThreadID else {
            refreshConversationState()
            return
        }

        guard changedThreadID == selectedThreadID else {
            return
        }

        refreshConversationState()
    }

    var activeTurnContextForSelectedThread: ActiveTurnContext? {
        guard let selectedThreadID,
              let context = activeTurnContextsByThreadID[selectedThreadID]
        else {
            return nil
        }

        return context
    }

    var activeTurnContext: ActiveTurnContext? {
        get {
            if let selectedThreadID,
               let selectedContext = activeTurnContextsByThreadID[selectedThreadID]
            {
                return selectedContext
            }

            return activeTurnContextsByThreadID
                .values
                .sorted(by: { $0.startedAt < $1.startedAt })
                .first
        }
        set {
            guard let newValue else {
                if let selectedThreadID {
                    _ = removeActiveTurnContext(for: selectedThreadID)
                } else if let oldestThreadID = activeTurnContextsByThreadID
                    .values
                    .sorted(by: { $0.startedAt < $1.startedAt })
                    .first?
                    .localThreadID
                {
                    _ = removeActiveTurnContext(for: oldestThreadID)
                }
                return
            }

            upsertActiveTurnContext(newValue)
        }
    }

    var isSelectedThreadWorking: Bool {
        guard let selectedThreadID else {
            return false
        }
        return activeTurnThreadIDs.contains(selectedThreadID)
    }

    func isThreadWorking(_ threadID: UUID) -> Bool {
        activeTurnThreadIDs.contains(threadID)
    }

    func activeTurnContext(for threadID: UUID) -> ActiveTurnContext? {
        activeTurnContextsByThreadID[threadID]
    }

    @discardableResult
    func updateActiveTurnContext(
        for threadID: UUID,
        mutate: (inout ActiveTurnContext) -> Void
    ) -> ActiveTurnContext? {
        guard var context = activeTurnContextsByThreadID[threadID] else {
            return nil
        }
        let previousRuntimeThreadID = context.runtimeThreadID
        mutate(&context)
        activeTurnContextsByThreadID[threadID] = context

        if previousRuntimeThreadID != context.runtimeThreadID,
           !previousRuntimeThreadID.isEmpty,
           localThreadIDByRuntimeThreadID[previousRuntimeThreadID] == threadID
        {
            localThreadIDByRuntimeThreadID.removeValue(forKey: previousRuntimeThreadID)
        }

        if !context.runtimeThreadID.isEmpty {
            runtimeThreadIDByLocalThreadID[threadID] = context.runtimeThreadID
            localThreadIDByRuntimeThreadID[context.runtimeThreadID] = threadID
        } else if runtimeThreadIDByLocalThreadID[threadID] == previousRuntimeThreadID {
            runtimeThreadIDByLocalThreadID.removeValue(forKey: threadID)
        }

        if let runtimeTurnID = context.runtimeTurnID,
           !runtimeTurnID.isEmpty
        {
            localThreadIDByRuntimeTurnID[runtimeTurnID] = threadID
        }
        pendingTurnStartThreadIDs.remove(threadID)
        syncActiveTurnPublishedState()
        return context
    }

    func upsertActiveTurnContext(_ context: ActiveTurnContext) {
        let previousRuntimeThreadID = activeTurnContextsByThreadID[context.localThreadID]?.runtimeThreadID
        activeTurnContextsByThreadID[context.localThreadID] = context

        if previousRuntimeThreadID != context.runtimeThreadID,
           let previousRuntimeThreadID,
           !previousRuntimeThreadID.isEmpty,
           localThreadIDByRuntimeThreadID[previousRuntimeThreadID] == context.localThreadID
        {
            localThreadIDByRuntimeThreadID.removeValue(forKey: previousRuntimeThreadID)
        }

        if !context.runtimeThreadID.isEmpty {
            runtimeThreadIDByLocalThreadID[context.localThreadID] = context.runtimeThreadID
            localThreadIDByRuntimeThreadID[context.runtimeThreadID] = context.localThreadID
        }

        if let runtimeTurnID = context.runtimeTurnID,
           !runtimeTurnID.isEmpty
        {
            localThreadIDByRuntimeTurnID[runtimeTurnID] = context.localThreadID
        }
        pendingTurnStartThreadIDs.remove(context.localThreadID)
        syncActiveTurnPublishedState()
    }

    @discardableResult
    func removeActiveTurnContext(for threadID: UUID) -> ActiveTurnContext? {
        let removed = activeTurnContextsByThreadID.removeValue(forKey: threadID)
        if let runtimeTurnID = removed?.runtimeTurnID,
           !runtimeTurnID.isEmpty
        {
            localThreadIDByRuntimeTurnID.removeValue(forKey: runtimeTurnID)
        }
        assistantMessageIDsByItemID[threadID] = [:]
        localThreadIDByCommandItemID = localThreadIDByCommandItemID.filter { $0.value != threadID }
        pendingTurnStartThreadIDs.remove(threadID)
        syncActiveTurnPublishedState()
        return removed
    }

    func markTurnStartPending(threadID: UUID) {
        let (inserted, _) = pendingTurnStartThreadIDs.insert(threadID)
        guard inserted else {
            return
        }
        syncActiveTurnPublishedState()
    }

    func clearTurnStartPending(threadID: UUID) {
        guard pendingTurnStartThreadIDs.remove(threadID) != nil else {
            return
        }
        syncActiveTurnPublishedState()
    }

    func localThreadID(for runtimeTurnID: String?) -> UUID? {
        guard let runtimeTurnID,
              !runtimeTurnID.isEmpty
        else {
            return nil
        }
        return localThreadIDByRuntimeTurnID[runtimeTurnID]
    }

    func clearActiveTurnContexts() {
        let activeThreadIDs = Set(activeTurnContextsByThreadID.keys)
        if !activeThreadIDs.isEmpty {
            assistantMessageIDsByItemID = assistantMessageIDsByItemID.filter { !activeThreadIDs.contains($0.key) }
            localThreadIDByCommandItemID = localThreadIDByCommandItemID.filter { !activeThreadIDs.contains($0.value) }
        }
        activeTurnContextsByThreadID.removeAll(keepingCapacity: false)
        localThreadIDByRuntimeTurnID.removeAll(keepingCapacity: false)
        pendingTurnStartThreadIDs.removeAll(keepingCapacity: false)
        syncActiveTurnPublishedState()
    }

    func syncActiveTurnPublishedState() {
        let nextActiveThreadIDs = Set(activeTurnContextsByThreadID.keys).union(pendingTurnStartThreadIDs)
        if activeTurnThreadIDs != nextActiveThreadIDs {
            activeTurnThreadIDs = nextActiveThreadIDs
        }

        let nextInProgress = !nextActiveThreadIDs.isEmpty
        if isTurnInProgress != nextInProgress {
            isTurnInProgress = nextInProgress
        }

        scheduleAdaptiveConcurrencyRefresh(reason: "active turn state changed")
    }

    func isThreadUnread(_ threadID: UUID) -> Bool {
        unreadThreadIDs.contains(threadID)
    }

    func markThreadUnreadIfNeeded(_ threadID: UUID) {
        guard selectedThreadID != threadID else {
            return
        }
        unreadThreadIDs.insert(threadID)
    }

    func clearUnreadMarker(for threadID: UUID?) {
        guard let threadID else {
            return
        }
        unreadThreadIDs.remove(threadID)
    }

    func syncApprovalPresentationState() {
        var combinedPendingThreadIDs = approvalStateMachine.pendingThreadIDs
        if let preview = pendingComputerActionPreview {
            combinedPendingThreadIDs.insert(preview.threadID)
        }
        if let notice = permissionRecoveryNotice,
           let threadID = notice.threadID
        {
            combinedPendingThreadIDs.insert(threadID)
        }

        pendingApprovalThreadIDs = combinedPendingThreadIDs
        if let selectedThreadRequest = pendingApprovalForSelectedThread {
            activeApprovalRequest = selectedThreadRequest
        } else {
            activeApprovalRequest = unscopedApprovalRequests.first
        }
    }
}
