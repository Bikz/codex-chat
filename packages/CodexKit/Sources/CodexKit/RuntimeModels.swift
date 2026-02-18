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

public enum CodexRuntimeEvent: Hashable, Sendable {
    case threadStarted(threadID: String)
    case turnStarted(turnID: String)
    case assistantMessageDelta(itemID: String, delta: String)
    case action(RuntimeAction)
    case turnCompleted(RuntimeTurnCompletion)
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
