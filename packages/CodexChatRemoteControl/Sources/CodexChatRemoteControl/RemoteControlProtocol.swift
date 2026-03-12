import Foundation

public enum RemoteControlProtocol {
    public static let schemaVersion = 2
}

public enum RemoteControlPeerRole: String, Codable, Sendable {
    case desktop
    case mobile
}

public enum RemoteControlCommandName: String, Codable, Sendable {
    case threadSendMessage = "thread.send_message"
    case threadSelect = "thread.select"
    case projectSelect = "project.select"
    case runtimeRequestRespond = "runtime_request.respond"
}

public enum RemoteControlCommandAckStatus: String, Codable, Sendable {
    case accepted
    case rejected
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
    public var supportsRuntimeRequests: Bool

    public init(role: RemoteControlPeerRole, clientName: String, supportsRuntimeRequests: Bool) {
        self.role = role
        self.clientName = clientName
        self.supportsRuntimeRequests = supportsRuntimeRequests
    }
}

public struct RemoteControlAuthOKPayload: Codable, Sendable, Equatable {
    public var connectionID: String
    public var role: RemoteControlPeerRole
    public var canRespondToRuntimeRequests: Bool

    public init(connectionID: String, role: RemoteControlPeerRole, canRespondToRuntimeRequests: Bool) {
        self.connectionID = connectionID
        self.role = role
        self.canRespondToRuntimeRequests = canRespondToRuntimeRequests
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
    public var isAwaitingRuntimeRequest: Bool

    public init(threadID: String, isTurnInProgress: Bool, isAwaitingRuntimeRequest: Bool) {
        self.threadID = threadID
        self.isTurnInProgress = isTurnInProgress
        self.isAwaitingRuntimeRequest = isAwaitingRuntimeRequest
    }
}

public enum RemoteControlRuntimeRequestKind: String, Codable, Sendable, Equatable {
    case approval
    case permissionsApproval
    case userInput
    case mcpElicitation
    case dynamicToolCall
}

public struct RemoteControlRuntimeRequestResponseOption: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct RemoteControlRuntimeRequestOption: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var description: String?

    public init(id: String, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

public struct RemoteControlRuntimeRequestSnapshot: Codable, Sendable, Equatable {
    public var requestID: String
    public var kind: RemoteControlRuntimeRequestKind
    public var threadID: String?
    public var title: String
    public var summary: String
    public var responseOptions: [RemoteControlRuntimeRequestResponseOption]
    public var permissions: [String]
    public var options: [RemoteControlRuntimeRequestOption]
    public var scopeHint: String?
    public var toolName: String?
    public var serverName: String?

    public init(
        requestID: String,
        kind: RemoteControlRuntimeRequestKind,
        threadID: String?,
        title: String,
        summary: String,
        responseOptions: [RemoteControlRuntimeRequestResponseOption],
        permissions: [String] = [],
        options: [RemoteControlRuntimeRequestOption] = [],
        scopeHint: String? = nil,
        toolName: String? = nil,
        serverName: String? = nil
    ) {
        self.requestID = requestID
        self.kind = kind
        self.threadID = threadID
        self.title = title
        self.summary = summary
        self.responseOptions = responseOptions
        self.permissions = permissions
        self.options = options
        self.scopeHint = scopeHint
        self.toolName = toolName
        self.serverName = serverName
    }
}

public struct RemoteControlSnapshotPayload: Codable, Sendable, Equatable {
    public var projects: [RemoteControlProjectSnapshot]
    public var threads: [RemoteControlThreadSnapshot]
    public var selectedProjectID: String?
    public var selectedThreadID: String?
    public var messages: [RemoteControlMessageSnapshot]
    public var turnState: RemoteControlTurnStateSnapshot?
    public var pendingRuntimeRequests: [RemoteControlRuntimeRequestSnapshot]

    public init(
        projects: [RemoteControlProjectSnapshot],
        threads: [RemoteControlThreadSnapshot],
        selectedProjectID: String?,
        selectedThreadID: String?,
        messages: [RemoteControlMessageSnapshot],
        turnState: RemoteControlTurnStateSnapshot?,
        pendingRuntimeRequests: [RemoteControlRuntimeRequestSnapshot]
    ) {
        self.projects = projects
        self.threads = threads
        self.selectedProjectID = selectedProjectID
        self.selectedThreadID = selectedThreadID
        self.messages = messages
        self.turnState = turnState
        self.pendingRuntimeRequests = pendingRuntimeRequests
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

public struct RemoteControlRuntimeRequestResponse: Codable, Sendable, Equatable {
    public var decision: String?
    public var permissions: [String]?
    public var scope: String?
    public var text: String?
    public var optionID: String?
    public var approved: Bool?

    public init(
        decision: String? = nil,
        permissions: [String]? = nil,
        scope: String? = nil,
        text: String? = nil,
        optionID: String? = nil,
        approved: Bool? = nil
    ) {
        self.decision = decision
        self.permissions = permissions
        self.scope = scope
        self.text = text
        self.optionID = optionID
        self.approved = approved
    }
}

public struct RemoteControlCommandPayload: Codable, Sendable, Equatable {
    public var name: RemoteControlCommandName
    public var commandID: String
    public var threadID: String?
    public var projectID: String?
    public var text: String?
    public var runtimeRequestID: String?
    public var runtimeRequestKind: RemoteControlRuntimeRequestKind?
    public var runtimeRequestResponse: RemoteControlRuntimeRequestResponse?

    public init(
        name: RemoteControlCommandName,
        commandID: String,
        threadID: String? = nil,
        projectID: String? = nil,
        text: String? = nil,
        runtimeRequestID: String? = nil,
        runtimeRequestKind: RemoteControlRuntimeRequestKind? = nil,
        runtimeRequestResponse: RemoteControlRuntimeRequestResponse? = nil
    ) {
        self.name = name
        self.commandID = commandID
        self.threadID = threadID
        self.projectID = projectID
        self.text = text
        self.runtimeRequestID = runtimeRequestID
        self.runtimeRequestKind = runtimeRequestKind
        self.runtimeRequestResponse = runtimeRequestResponse
    }
}

public struct RemoteControlCommandAckPayload: Codable, Sendable, Equatable {
    public var commandSeq: UInt64
    public var commandID: String
    public var commandName: RemoteControlCommandName
    public var status: RemoteControlCommandAckStatus
    public var reason: String?
    public var threadID: String?

    public init(
        commandSeq: UInt64,
        commandID: String,
        commandName: RemoteControlCommandName,
        status: RemoteControlCommandAckStatus,
        reason: String? = nil,
        threadID: String? = nil
    ) {
        self.commandSeq = commandSeq
        self.commandID = commandID
        self.commandName = commandName
        self.status = status
        self.reason = reason
        self.threadID = threadID
    }
}

public enum RemoteControlPayload: Sendable, Equatable {
    case hello(RemoteControlHelloPayload)
    case authOK(RemoteControlAuthOKPayload)
    case snapshot(RemoteControlSnapshotPayload)
    case event(RemoteControlEventPayload)
    case command(RemoteControlCommandPayload)
    case commandAck(RemoteControlCommandAckPayload)
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
        case commandAck = "command_ack"
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
        case .commandAck:
            self = try .commandAck(container.decode(RemoteControlCommandAckPayload.self, forKey: .payload))
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
        case let .commandAck(payload):
            try container.encode(PayloadType.commandAck, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}
