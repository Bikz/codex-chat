import Foundation

public enum ProjectTrustState: String, CaseIterable, Hashable, Sendable, Codable {
    case untrusted
    case trusted
}

public struct ProjectRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var path: String
    public var trustState: ProjectTrustState
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        trustState: ProjectTrustState,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.trustState = trustState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
