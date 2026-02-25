import Foundation

public enum RemoteControlProtocol {
    public static let schemaVersion = 1
}

public enum RemoteControlPeerRole: String, Codable, Sendable {
    case desktop
    case mobile
}

public enum RemoteControlCommandName: String, Codable, Sendable {
    case threadSendMessage = "thread.send_message"
    case threadSelect = "thread.select"
    case projectSelect = "project.select"
    case approvalRespond = "approval.respond"
}

public struct RemoteControlEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var sessionID: String
    public var seq: UInt64
    public var timestamp: Date
    public var payload: RemoteControlPayload

    public init(
        schemaVersion: Int = RemoteControlProtocol.schemaVersion,
        sessionID: String,
        seq: UInt64,
        timestamp: Date = Date(),
        payload: RemoteControlPayload
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.seq = seq
        self.timestamp = timestamp
        self.payload = payload
    }
}

public struct RemoteControlHelloPayload: Codable, Sendable, Equatable {
    public var role: RemoteControlPeerRole
    public var clientName: String
    public var supportsApprovals: Bool

    public init(role: RemoteControlPeerRole, clientName: String, supportsApprovals: Bool) {
        self.role = role
        self.clientName = clientName
        self.supportsApprovals = supportsApprovals
    }
}

public struct RemoteControlAuthOKPayload: Codable, Sendable, Equatable {
    public var connectionID: String
    public var role: RemoteControlPeerRole
    public var canApproveRemotely: Bool

    public init(connectionID: String, role: RemoteControlPeerRole, canApproveRemotely: Bool) {
        self.connectionID = connectionID
        self.role = role
        self.canApproveRemotely = canApproveRemotely
    }
}

public struct RemoteControlProjectSnapshot: Codable, Sendable, Equatable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct RemoteControlThreadSnapshot: Codable, Sendable, Equatable {
    public var id: String
    public var projectID: String
    public var title: String
    public var isPinned: Bool

    public init(id: String, projectID: String, title: String, isPinned: Bool) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.isPinned = isPinned
    }
}

public struct RemoteControlMessageSnapshot: Codable, Sendable, Equatable {
    public var id: String
    public var threadID: String
    public var role: String
    public var text: String
    public var createdAt: Date

    public init(id: String, threadID: String, role: String, text: String, createdAt: Date) {
        self.id = id
        self.threadID = threadID
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public struct RemoteControlTurnStateSnapshot: Codable, Sendable, Equatable {
    public var threadID: String
    public var isTurnInProgress: Bool
    public var isAwaitingApproval: Bool

    public init(threadID: String, isTurnInProgress: Bool, isAwaitingApproval: Bool) {
        self.threadID = threadID
        self.isTurnInProgress = isTurnInProgress
        self.isAwaitingApproval = isAwaitingApproval
    }
}

public struct RemoteControlApprovalSnapshot: Codable, Sendable, Equatable {
    public var requestID: String
    public var threadID: String?
    public var summary: String

    public init(requestID: String, threadID: String?, summary: String) {
        self.requestID = requestID
        self.threadID = threadID
        self.summary = summary
    }
}

public struct RemoteControlSnapshotPayload: Codable, Sendable, Equatable {
    public var projects: [RemoteControlProjectSnapshot]
    public var threads: [RemoteControlThreadSnapshot]
    public var selectedProjectID: String?
    public var selectedThreadID: String?
    public var messages: [RemoteControlMessageSnapshot]
    public var turnState: RemoteControlTurnStateSnapshot?
    public var pendingApprovals: [RemoteControlApprovalSnapshot]

    public init(
        projects: [RemoteControlProjectSnapshot],
        threads: [RemoteControlThreadSnapshot],
        selectedProjectID: String?,
        selectedThreadID: String?,
        messages: [RemoteControlMessageSnapshot],
        turnState: RemoteControlTurnStateSnapshot?,
        pendingApprovals: [RemoteControlApprovalSnapshot]
    ) {
        self.projects = projects
        self.threads = threads
        self.selectedProjectID = selectedProjectID
        self.selectedThreadID = selectedThreadID
        self.messages = messages
        self.turnState = turnState
        self.pendingApprovals = pendingApprovals
    }
}

public struct RemoteControlEventPayload: Codable, Sendable, Equatable {
    public var name: String
    public var threadID: String?
    public var body: String?
    public var messageID: String?
    public var role: String?
    public var createdAt: Date?

    public init(
        name: String,
        threadID: String?,
        body: String?,
        messageID: String? = nil,
        role: String? = nil,
        createdAt: Date? = nil
    ) {
        self.name = name
        self.threadID = threadID
        self.body = body
        self.messageID = messageID
        self.role = role
        self.createdAt = createdAt
    }
}

public struct RemoteControlCommandPayload: Codable, Sendable, Equatable {
    public var name: RemoteControlCommandName
    public var threadID: String?
    public var projectID: String?
    public var text: String?
    public var approvalRequestID: String?
    public var approvalDecision: String?

    public init(
        name: RemoteControlCommandName,
        threadID: String? = nil,
        projectID: String? = nil,
        text: String? = nil,
        approvalRequestID: String? = nil,
        approvalDecision: String? = nil
    ) {
        self.name = name
        self.threadID = threadID
        self.projectID = projectID
        self.text = text
        self.approvalRequestID = approvalRequestID
        self.approvalDecision = approvalDecision
    }
}

public enum RemoteControlPayload: Sendable, Equatable {
    case hello(RemoteControlHelloPayload)
    case authOK(RemoteControlAuthOKPayload)
    case snapshot(RemoteControlSnapshotPayload)
    case event(RemoteControlEventPayload)
    case command(RemoteControlCommandPayload)
}

extension RemoteControlPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum PayloadType: String, Codable {
        case hello
        case authOK = "auth_ok"
        case snapshot
        case event
        case command
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PayloadType.self, forKey: .type)

        switch type {
        case .hello:
            self = try .hello(container.decode(RemoteControlHelloPayload.self, forKey: .payload))
        case .authOK:
            self = try .authOK(container.decode(RemoteControlAuthOKPayload.self, forKey: .payload))
        case .snapshot:
            self = try .snapshot(container.decode(RemoteControlSnapshotPayload.self, forKey: .payload))
        case .event:
            self = try .event(container.decode(RemoteControlEventPayload.self, forKey: .payload))
        case .command:
            self = try .command(container.decode(RemoteControlCommandPayload.self, forKey: .payload))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .hello(payload):
            try container.encode(PayloadType.hello, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .authOK(payload):
            try container.encode(PayloadType.authOK, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .snapshot(payload):
            try container.encode(PayloadType.snapshot, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .event(payload):
            try container.encode(PayloadType.event, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .command(payload):
            try container.encode(PayloadType.command, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}
