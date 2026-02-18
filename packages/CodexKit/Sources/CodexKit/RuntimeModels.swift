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
