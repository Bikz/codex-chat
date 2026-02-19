import Foundation

public enum ProjectTrustState: String, CaseIterable, Hashable, Sendable, Codable {
    case untrusted
    case trusted
}

public enum ProjectSandboxMode: String, CaseIterable, Hashable, Sendable, Codable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

public extension ProjectSandboxMode {
    var title: String {
        switch self {
        case .readOnly:
            "Read-only"
        case .workspaceWrite:
            "Workspace-write"
        case .dangerFullAccess:
            "Danger full access"
        }
    }
}

public enum ProjectApprovalPolicy: String, CaseIterable, Hashable, Sendable, Codable {
    case untrusted
    case onRequest = "on-request"
    case never
}

public extension ProjectApprovalPolicy {
    var title: String {
        switch self {
        case .untrusted:
            "Untrusted"
        case .onRequest:
            "On request"
        case .never:
            "Never"
        }
    }
}

public enum ProjectWebSearchMode: String, CaseIterable, Hashable, Sendable, Codable {
    case cached
    case live
    case disabled
}

public extension ProjectWebSearchMode {
    var title: String {
        switch self {
        case .cached:
            "Cached"
        case .live:
            "Live"
        case .disabled:
            "Disabled"
        }
    }
}

public enum ProjectMemoryWriteMode: String, CaseIterable, Hashable, Sendable, Codable {
    case off
    case summariesOnly = "summaries-only"
    case summariesAndKeyFacts = "summaries-and-key-facts"
}

public struct ProjectMemorySettings: Hashable, Sendable, Codable {
    public var writeMode: ProjectMemoryWriteMode
    public var embeddingsEnabled: Bool

    public init(writeMode: ProjectMemoryWriteMode, embeddingsEnabled: Bool) {
        self.writeMode = writeMode
        self.embeddingsEnabled = embeddingsEnabled
    }
}

public struct ProjectSafetySettings: Hashable, Sendable, Codable {
    public var sandboxMode: ProjectSandboxMode
    public var approvalPolicy: ProjectApprovalPolicy
    public var networkAccess: Bool
    public var webSearch: ProjectWebSearchMode

    public init(
        sandboxMode: ProjectSandboxMode,
        approvalPolicy: ProjectApprovalPolicy,
        networkAccess: Bool,
        webSearch: ProjectWebSearchMode
    ) {
        self.sandboxMode = sandboxMode
        self.approvalPolicy = approvalPolicy
        self.networkAccess = networkAccess
        self.webSearch = webSearch
    }
}

public enum SkillInstallScope: String, CaseIterable, Hashable, Sendable, Codable {
    case project
    case global
}

public enum SkillEnablementTarget: String, CaseIterable, Hashable, Sendable, Codable {
    case global
    case general
    case project
}

public enum SkillUpdateCapability: String, CaseIterable, Hashable, Sendable, Codable {
    case gitUpdate
    case reinstall
    case unavailable
}

public struct ProjectSkillEnablementRecord: Hashable, Sendable, Codable {
    public let projectID: UUID
    public let skillPath: String
    public let enabled: Bool
    public let updatedAt: Date

    public init(projectID: UUID, skillPath: String, enabled: Bool, updatedAt: Date = Date()) {
        self.projectID = projectID
        self.skillPath = skillPath
        self.enabled = enabled
        self.updatedAt = updatedAt
    }
}

public struct ProjectRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var path: String
    public var isGeneralProject: Bool
    public var trustState: ProjectTrustState
    public var sandboxMode: ProjectSandboxMode
    public var approvalPolicy: ProjectApprovalPolicy
    public var networkAccess: Bool
    public var webSearch: ProjectWebSearchMode
    public var memoryWriteMode: ProjectMemoryWriteMode
    public var memoryEmbeddingsEnabled: Bool
    public var uiModPath: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        isGeneralProject: Bool = false,
        trustState: ProjectTrustState,
        sandboxMode: ProjectSandboxMode = .readOnly,
        approvalPolicy: ProjectApprovalPolicy = .untrusted,
        networkAccess: Bool = false,
        webSearch: ProjectWebSearchMode = .cached,
        memoryWriteMode: ProjectMemoryWriteMode = .off,
        memoryEmbeddingsEnabled: Bool = false,
        uiModPath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.isGeneralProject = isGeneralProject
        self.trustState = trustState
        self.sandboxMode = sandboxMode
        self.approvalPolicy = approvalPolicy
        self.networkAccess = networkAccess
        self.webSearch = webSearch
        self.memoryWriteMode = memoryWriteMode
        self.memoryEmbeddingsEnabled = memoryEmbeddingsEnabled
        self.uiModPath = uiModPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public extension ProjectSafetySettings {
    static func recommendedDefaults(for trustState: ProjectTrustState) -> ProjectSafetySettings {
        switch trustState {
        case .trusted:
            ProjectSafetySettings(
                sandboxMode: .workspaceWrite,
                approvalPolicy: .onRequest,
                networkAccess: false,
                webSearch: .cached
            )
        case .untrusted:
            ProjectSafetySettings(
                sandboxMode: .readOnly,
                approvalPolicy: .untrusted,
                networkAccess: false,
                webSearch: .cached
            )
        }
    }
}

public struct ThreadRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let projectId: UUID
    public var title: String
    public var isPinned: Bool
    public var archivedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        title: String,
        isPinned: Bool = false,
        archivedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.isPinned = isPinned
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum FollowUpSource: String, Codable, Hashable, Sendable {
    case userQueued
    case assistantSuggestion
}

public enum FollowUpDispatchMode: String, Codable, Hashable, Sendable {
    case auto
    case manual
}

public enum FollowUpState: String, Codable, Hashable, Sendable {
    case pending
    case failed
}

public struct FollowUpQueueItemRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let threadID: UUID
    public let source: FollowUpSource
    public var dispatchMode: FollowUpDispatchMode
    public var state: FollowUpState
    public var text: String
    public var sortIndex: Int
    public var originTurnID: String?
    public var originSuggestionID: String?
    public var lastError: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        threadID: UUID,
        source: FollowUpSource,
        dispatchMode: FollowUpDispatchMode,
        state: FollowUpState = .pending,
        text: String,
        sortIndex: Int,
        originTurnID: String? = nil,
        originSuggestionID: String? = nil,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.source = source
        self.dispatchMode = dispatchMode
        self.state = state
        self.text = text
        self.sortIndex = sortIndex
        self.originTurnID = originTurnID
        self.originSuggestionID = originSuggestionID
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RuntimeThreadMappingRecord: Hashable, Sendable, Codable {
    public let localThreadID: UUID
    public let runtimeThreadID: String
    public let updatedAt: Date

    public init(localThreadID: UUID, runtimeThreadID: String, updatedAt: Date = Date()) {
        self.localThreadID = localThreadID
        self.runtimeThreadID = runtimeThreadID
        self.updatedAt = updatedAt
    }
}

public struct ProjectSecretRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let projectID: UUID
    public var name: String
    public var keychainAccount: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        name: String,
        keychainAccount: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.keychainAccount = keychainAccount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AppPreferenceRecord: Hashable, Sendable, Codable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public enum TranscriptDetailLevel: String, CaseIterable, Sendable, Codable {
    case chat
    case balanced
    case detailed
}

public enum AppPreferenceKey: String, CaseIterable, Sendable {
    case lastOpenedProjectID = "last_opened_project_id"
    case lastOpenedThreadID = "last_opened_thread_id"
    case globalUIModPath = "global_ui_mod_path"
    case untrustedShellAcknowledgements = "untrusted_shell_acknowledgements"
    case runtimeDefaultModel = "runtime.default.model"
    case runtimeDefaultReasoning = "runtime.default.reasoning"
    case runtimeDefaultWebSearch = "runtime.default.web_search"
    case runtimeDefaultSafety = "runtime.default.safety"
    case generalProjectSafetyMigrationV1 = "general_project_safety_migration_v1"
    case runtimeConfigMigrationV1 = "runtime_config_migration_v1"
    case extensionsBackgroundAutomationPermission = "extensions.background_automation_permission"
    case extensionsModsBarVisibilityByThread = "extensions.mods_bar_visibility_by_thread"
    case extensionsLegacyModsBarVisibility = "extensions.inspector_visibility_by_thread"
    case advancedExecutableModsUnlock = "mods.advanced_executable_unlock"
    case advancedExecutableModsMigrationV1 = "mods.advanced_executable_unlock_migration_v1"
    case workerTraceCacheByTurn = "runtime.worker_trace_cache_by_turn"
    case transcriptDetailLevel = "transcript_detail_level"
}

public enum ExtensionInstallScope: String, CaseIterable, Hashable, Sendable, Codable {
    case global
    case project
}

public struct ExtensionInstallRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let modID: String
    public let scope: ExtensionInstallScope
    public let projectID: UUID?
    public var sourceURL: String?
    public var installedPath: String
    public var enabled: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        modID: String,
        scope: ExtensionInstallScope,
        projectID: UUID? = nil,
        sourceURL: String? = nil,
        installedPath: String,
        enabled: Bool,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.modID = modID
        self.scope = scope
        self.projectID = projectID
        self.sourceURL = sourceURL
        self.installedPath = installedPath
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ExtensionPermissionKey: String, CaseIterable, Hashable, Sendable, Codable {
    case projectRead
    case projectWrite
    case network
    case runtimeControl
    case runWhenAppClosed
}

public enum ExtensionPermissionStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case granted
    case denied
}

public struct ExtensionPermissionRecord: Hashable, Sendable, Codable {
    public let modID: String
    public let permissionKey: ExtensionPermissionKey
    public var status: ExtensionPermissionStatus
    public var grantedAt: Date

    public init(
        modID: String,
        permissionKey: ExtensionPermissionKey,
        status: ExtensionPermissionStatus,
        grantedAt: Date = Date()
    ) {
        self.modID = modID
        self.permissionKey = permissionKey
        self.status = status
        self.grantedAt = grantedAt
    }
}

public struct ExtensionHookStateRecord: Hashable, Sendable, Codable {
    public let modID: String
    public let hookID: String
    public var lastRunAt: Date?
    public var lastStatus: String
    public var lastError: String?

    public init(
        modID: String,
        hookID: String,
        lastRunAt: Date? = nil,
        lastStatus: String,
        lastError: String? = nil
    ) {
        self.modID = modID
        self.hookID = hookID
        self.lastRunAt = lastRunAt
        self.lastStatus = lastStatus
        self.lastError = lastError
    }
}

public struct ExtensionAutomationStateRecord: Hashable, Sendable, Codable {
    public let modID: String
    public let automationID: String
    public var nextRunAt: Date?
    public var lastRunAt: Date?
    public var lastStatus: String
    public var lastError: String?
    public var launchdLabel: String?

    public init(
        modID: String,
        automationID: String,
        nextRunAt: Date? = nil,
        lastRunAt: Date? = nil,
        lastStatus: String,
        lastError: String? = nil,
        launchdLabel: String? = nil
    ) {
        self.modID = modID
        self.automationID = automationID
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
        self.lastStatus = lastStatus
        self.lastError = lastError
        self.launchdLabel = launchdLabel
    }
}

public enum ComputerActionSafetyLevel: String, CaseIterable, Hashable, Sendable, Codable {
    case readOnly = "read-only"
    case externallyVisible = "externally-visible"
    case destructive
}

public enum ComputerActionPermissionDecision: String, CaseIterable, Hashable, Sendable, Codable {
    case granted
    case denied
}

public struct ComputerActionPermissionRecord: Hashable, Sendable, Codable {
    public let actionID: String
    public let projectID: UUID?
    public var decision: ComputerActionPermissionDecision
    public var decidedAt: Date

    public init(
        actionID: String,
        projectID: UUID? = nil,
        decision: ComputerActionPermissionDecision,
        decidedAt: Date = Date()
    ) {
        self.actionID = actionID
        self.projectID = projectID
        self.decision = decision
        self.decidedAt = decidedAt
    }
}

public enum ComputerActionRunPhase: String, CaseIterable, Hashable, Sendable, Codable {
    case preview
    case execute
    case undo
}

public enum ComputerActionRunStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case previewReady = "preview-ready"
    case awaitingConfirmation = "awaiting-confirmation"
    case executed
    case failed
    case denied
    case undone
}

public struct ComputerActionRunRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let actionID: String
    public let runContextID: String
    public let threadID: UUID?
    public let projectID: UUID?
    public var phase: ComputerActionRunPhase
    public var status: ComputerActionRunStatus
    public var previewArtifact: String?
    public var summary: String?
    public var errorMessage: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        actionID: String,
        runContextID: String,
        threadID: UUID? = nil,
        projectID: UUID? = nil,
        phase: ComputerActionRunPhase,
        status: ComputerActionRunStatus,
        previewArtifact: String? = nil,
        summary: String? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.actionID = actionID
        self.runContextID = runContextID
        self.threadID = threadID
        self.projectID = projectID
        self.phase = phase
        self.status = status
        self.previewArtifact = previewArtifact
        self.summary = summary
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum PlanRunStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

public struct PlanRunRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let threadID: UUID
    public let projectID: UUID
    public var title: String
    public var sourcePath: String?
    public var status: PlanRunStatus
    public var totalTasks: Int
    public var completedTasks: Int
    public var lastError: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        threadID: UUID,
        projectID: UUID,
        title: String,
        sourcePath: String? = nil,
        status: PlanRunStatus = .pending,
        totalTasks: Int = 0,
        completedTasks: Int = 0,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.projectID = projectID
        self.title = title
        self.sourcePath = sourcePath
        self.status = status
        self.totalTasks = totalTasks
        self.completedTasks = completedTasks
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum PlanTaskRunStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case pending
    case running
    case completed
    case failed
    case skipped
}

public struct PlanRunTaskRecord: Hashable, Sendable, Codable {
    public let planRunID: UUID
    public let taskID: String
    public var title: String
    public var dependencyIDs: [String]
    public var status: PlanTaskRunStatus
    public var updatedAt: Date

    public init(
        planRunID: UUID,
        taskID: String,
        title: String,
        dependencyIDs: [String] = [],
        status: PlanTaskRunStatus = .pending,
        updatedAt: Date = Date()
    ) {
        self.planRunID = planRunID
        self.taskID = taskID
        self.title = title
        self.dependencyIDs = dependencyIDs
        self.status = status
        self.updatedAt = updatedAt
    }
}

public enum ChatMessageRole: String, Codable, Hashable, Sendable {
    case user
    case assistant
    case system
}

public struct ChatMessage: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let threadId: UUID
    public let role: ChatMessageRole
    public var text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), threadId: UUID, role: ChatMessageRole, text: String, createdAt: Date = Date()) {
        self.id = id
        self.threadId = threadId
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public struct ActionCard: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let threadID: UUID
    public let method: String
    public let title: String
    public let detail: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        threadID: UUID,
        method: String,
        title: String,
        detail: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.method = method
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
    }
}

public enum TranscriptEntry: Identifiable, Hashable, Sendable {
    case message(ChatMessage)
    case actionCard(ActionCard)

    public var id: UUID {
        switch self {
        case let .message(message):
            message.id
        case let .actionCard(card):
            card.id
        }
    }

    public var threadID: UUID {
        switch self {
        case let .message(message):
            message.threadId
        case let .actionCard(card):
            card.threadID
        }
    }
}

public struct ChatSearchResult: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let threadID: UUID
    public let projectID: UUID
    public let source: String
    public let excerpt: String

    public init(
        id: UUID = UUID(),
        threadID: UUID,
        projectID: UUID,
        source: String,
        excerpt: String
    ) {
        self.id = id
        self.threadID = threadID
        self.projectID = projectID
        self.source = source
        self.excerpt = excerpt
    }
}

public enum CodexChatCoreError: LocalizedError, Sendable {
    case missingRecord(String)

    public var errorDescription: String? {
        switch self {
        case let .missingRecord(identifier):
            "Required record was not found: \(identifier)"
        }
    }
}
