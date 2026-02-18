import CodexKit
import Foundation

struct ThreadLogEntry: Identifiable, Hashable {
    let id: UUID
    let threadID: UUID
    let timestamp: Date
    let level: LogLevel
    let text: String

    init(
        id: UUID = UUID(),
        threadID: UUID,
        timestamp: Date = Date(),
        level: LogLevel,
        text: String
    ) {
        self.id = id
        self.threadID = threadID
        self.timestamp = timestamp
        self.level = level
        self.text = text
    }
}
