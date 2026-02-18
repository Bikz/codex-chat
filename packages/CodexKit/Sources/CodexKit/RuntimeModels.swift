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
    public let title: String
    public let detail: String

    public init(method: String, itemID: String?, itemType: String?, title: String, detail: String) {
        self.method = method
        self.itemID = itemID
        self.itemType = itemType
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

public enum CodexRuntimeEvent: Hashable, Sendable {
    case threadStarted(threadID: String)
    case turnStarted(turnID: String)
    case assistantMessageDelta(itemID: String, delta: String)
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
            return "Codex CLI was not found on PATH."
        case .processNotRunning:
            return "Codex runtime process is not running."
        case .handshakeFailed(let detail):
            return "Codex runtime handshake failed: \(detail)"
        case .timedOut(let operation):
            return "Codex runtime timed out while \(operation)."
        case .invalidResponse(let detail):
            return "Codex runtime returned an invalid response: \(detail)"
        case .rpcError(_, let message):
            return "Codex runtime RPC error: \(message)"
        case .transportClosed:
            return "Codex runtime transport closed unexpectedly."
        }
    }
}
