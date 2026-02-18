import Foundation

public enum RuntimeStatus: String, CaseIterable, Codable, Sendable {
    case idle
    case starting
    case connected
    case error
}

public enum LogLevel: String, Codable, Sendable {
    case debug
    case info
    case warning
    case error
}

public struct LogEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

public struct RuntimeAction: Hashable, Sendable {
    public let method: String
    public let itemID: String?
    public let itemType: String?
    public let threadID: String?
    public let turnID: String?
    public let title: String
    public let detail: String

    public init(
        method: String,
        itemID: String?,
        itemType: String?,
        threadID: String?,
        turnID: String?,
        title: String,
        detail: String
    ) {
        self.method = method
        self.itemID = itemID
        self.itemType = itemType
        self.threadID = threadID
        self.turnID = turnID
        self.title = title
        self.detail = detail
    }
}

public struct RuntimeTurnCompletion: Hashable, Sendable {
    public let turnID: String?
    public let status: String
    public let errorMessage: String?

    public init(turnID: String?, status: String, errorMessage: String?) {
        self.turnID = turnID
        self.status = status
        self.errorMessage = errorMessage
    }
}

public enum RuntimeAuthMode: String, Codable, Sendable {
    case apiKey = "apikey"
    case chatGPT = "chatgpt"
    case chatGPTAuthTokens = "chatgptAuthTokens"
    case unknown

    public init(rawMode: String?) {
        switch rawMode {
        case RuntimeAuthMode.apiKey.rawValue:
            self = .apiKey
        case RuntimeAuthMode.chatGPT.rawValue:
            self = .chatGPT
        case RuntimeAuthMode.chatGPTAuthTokens.rawValue:
            self = .chatGPTAuthTokens
        default:
            self = .unknown
        }
    }
}

public struct RuntimeAccountSummary: Hashable, Sendable, Codable {
    public let type: String
    public let email: String?
    public let planType: String?

    public init(type: String, email: String?, planType: String?) {
        self.type = type
        self.email = email
        self.planType = planType
    }
}

public struct RuntimeAccountState: Hashable, Sendable, Codable {
    public let account: RuntimeAccountSummary?
    public let authMode: RuntimeAuthMode
    public let requiresOpenAIAuth: Bool

    public init(account: RuntimeAccountSummary?, authMode: RuntimeAuthMode, requiresOpenAIAuth: Bool) {
        self.account = account
        self.authMode = authMode
        self.requiresOpenAIAuth = requiresOpenAIAuth
    }

    public static let signedOut = RuntimeAccountState(
        account: nil,
        authMode: .unknown,
        requiresOpenAIAuth: true
    )
}

public struct RuntimeChatGPTLoginStart: Hashable, Sendable {
    public let loginID: String?
    public let authURL: URL

    public init(loginID: String?, authURL: URL) {
        self.loginID = loginID
        self.authURL = authURL
    }
}

public struct RuntimeLoginCompleted: Hashable, Sendable {
    public let loginID: String?
    public let success: Bool
    public let error: String?

    public init(loginID: String?, success: Bool, error: String?) {
        self.loginID = loginID
        self.success = success
        self.error = error
    }
}

public enum RuntimeSandboxMode: String, Hashable, Sendable, Codable {
    case readOnly
    case workspaceWrite
    case dangerFullAccess
}

public enum RuntimeApprovalPolicy: String, Hashable, Sendable, Codable {
    case untrusted = "unlessTrusted"
    case onRequest
    case never
}

public enum RuntimeWebSearchMode: String, Hashable, Sendable, Codable {
    case cached
    case live
    case disabled
}

public struct RuntimeSafetyConfiguration: Hashable, Sendable, Codable {
    public let sandboxMode: RuntimeSandboxMode
    public let approvalPolicy: RuntimeApprovalPolicy
    public let networkAccess: Bool
    public let webSearch: RuntimeWebSearchMode
    public let writableRoots: [String]

    public init(
        sandboxMode: RuntimeSandboxMode,
        approvalPolicy: RuntimeApprovalPolicy,
        networkAccess: Bool,
        webSearch: RuntimeWebSearchMode,
        writableRoots: [String]
    ) {
        self.sandboxMode = sandboxMode
        self.approvalPolicy = approvalPolicy
        self.networkAccess = networkAccess
        self.webSearch = webSearch
        self.writableRoots = writableRoots
    }
}

public struct RuntimeSkillInput: Hashable, Sendable, Codable {
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public enum RuntimeApprovalKind: String, Hashable, Sendable, Codable {
    case commandExecution
    case fileChange
    case unknown
}

public enum RuntimeApprovalDecision: Hashable, Sendable {
    case approveOnce
    case approveForSession
    case decline
    case cancel

    var rpcResult: JSONValue {
        switch self {
        case .approveOnce:
            .string("accept")
        case .approveForSession:
            .string("acceptForSession")
        case .decline:
            .string("decline")
        case .cancel:
            .string("cancel")
        }
    }
}

public struct RuntimeFileChange: Hashable, Sendable, Codable {
    public let path: String
    public let kind: String
    public let diff: String?

    public init(path: String, kind: String, diff: String?) {
        self.path = path
        self.kind = kind
        self.diff = diff
    }
}

public struct RuntimeFileChangeUpdate: Hashable, Sendable, Codable {
    public let itemID: String?
    public let threadID: String?
    public let turnID: String?
    public let status: String?
    public let changes: [RuntimeFileChange]

    public init(
        itemID: String?,
        threadID: String?,
        turnID: String?,
        status: String?,
        changes: [RuntimeFileChange]
    ) {
        self.itemID = itemID
        self.threadID = threadID
        self.turnID = turnID
        self.status = status
        self.changes = changes
    }
}

public struct RuntimeCommandOutputDelta: Hashable, Sendable, Codable {
    public let itemID: String
    public let threadID: String?
    public let turnID: String?
    public let delta: String

    public init(itemID: String, threadID: String?, turnID: String?, delta: String) {
        self.itemID = itemID
        self.threadID = threadID
        self.turnID = turnID
        self.delta = delta
    }
}

public struct RuntimeApprovalRequest: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let kind: RuntimeApprovalKind
    public let method: String
    public let threadID: String?
    public let turnID: String?
    public let itemID: String?
    public let reason: String?
    public let risk: String?
    public let cwd: String?
    public let command: [String]
    public let changes: [RuntimeFileChange]
    public let detail: String

    public init(
        id: Int,
        kind: RuntimeApprovalKind,
        method: String,
        threadID: String?,
        turnID: String?,
        itemID: String?,
        reason: String?,
        risk: String?,
        cwd: String?,
        command: [String],
        changes: [RuntimeFileChange],
        detail: String
    ) {
        self.id = id
        self.kind = kind
        self.method = method
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.reason = reason
        self.risk = risk
        self.cwd = cwd
        self.command = command
        self.changes = changes
        self.detail = detail
    }
}

public enum CodexRuntimeEvent: Hashable, Sendable {
    case threadStarted(threadID: String)
    case turnStarted(turnID: String)
    case assistantMessageDelta(itemID: String, delta: String)
    case commandOutputDelta(RuntimeCommandOutputDelta)
    case fileChangesUpdated(RuntimeFileChangeUpdate)
    case approvalRequested(RuntimeApprovalRequest)
    case action(RuntimeAction)
    case turnCompleted(RuntimeTurnCompletion)
    case accountUpdated(authMode: RuntimeAuthMode)
    case accountLoginCompleted(RuntimeLoginCompleted)
}

public enum CodexRuntimeError: LocalizedError, Sendable {
    case binaryNotFound
    case processNotRunning
    case handshakeFailed(String)
    case timedOut(String)
    case invalidResponse(String)
    case rpcError(code: Int, message: String)
    case transportClosed

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            "Codex CLI was not found on PATH."
        case .processNotRunning:
            "Codex runtime process is not running."
        case let .handshakeFailed(detail):
            "Codex runtime handshake failed: \(detail)"
        case let .timedOut(operation):
            "Codex runtime timed out while \(operation)."
        case let .invalidResponse(detail):
            "Codex runtime returned an invalid response: \(detail)"
        case let .rpcError(_, message):
            "Codex runtime RPC error: \(message)"
        case .transportClosed:
            "Codex runtime transport closed unexpectedly."
        }
    }
}
