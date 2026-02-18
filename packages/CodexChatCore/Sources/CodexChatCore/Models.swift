import Foundation

public struct ProjectRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
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

public enum CodexChatCoreError: LocalizedError, Sendable {
    case missingRecord(String)

    public var errorDescription: String? {
        switch self {
        case .missingRecord(let identifier):
            return "Required record was not found: \(identifier)"
        }
    }
}
