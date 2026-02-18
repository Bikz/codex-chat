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

public enum ProjectApprovalPolicy: String, CaseIterable, Hashable, Sendable, Codable {
    case untrusted
    case onRequest = "on-request"
    case never
}

public enum ProjectWebSearchMode: String, CaseIterable, Hashable, Sendable, Codable {
    case cached
    case live
    case disabled
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
            return ProjectSafetySettings(
                sandboxMode: .workspaceWrite,
                approvalPolicy: .onRequest,
                networkAccess: false,
                webSearch: .cached
            )
        case .untrusted:
            return ProjectSafetySettings(
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
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
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

public enum AppPreferenceKey: String, CaseIterable, Sendable {
    case lastOpenedProjectID = "last_opened_project_id"
    case lastOpenedThreadID = "last_opened_thread_id"
    case globalUIModPath = "global_ui_mod_path"
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
        case .message(let message):
            return message.id
        case .actionCard(let card):
            return card.id
        }
    }

    public var threadID: UUID {
        switch self {
        case .message(let message):
            return message.threadId
        case .actionCard(let card):
            return card.threadID
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
        case .missingRecord(let identifier):
            return "Required record was not found: \(identifier)"
        }
    }
}
