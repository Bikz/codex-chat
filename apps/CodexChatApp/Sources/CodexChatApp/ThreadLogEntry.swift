import CodexKit
import Foundation

struct ThreadLogEntry: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let text: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        text: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.text = text
    }
}
