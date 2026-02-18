import CodexChatCore
import Foundation
import GRDB

private struct ExtensionAutomationStateEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "extension_automation_state"

    var modID: String
    var automationID: String
    var nextRunAt: Date?
    var lastRunAt: Date?
    var lastStatus: String
    var lastError: String?
    var launchdLabel: String?

    init(record: ExtensionAutomationStateRecord) {
        modID = record.modID
        automationID = record.automationID
        nextRunAt = record.nextRunAt
        lastRunAt = record.lastRunAt
        lastStatus = record.lastStatus
        lastError = record.lastError
        launchdLabel = record.launchdLabel
    }

    var record: ExtensionAutomationStateRecord {
        ExtensionAutomationStateRecord(
            modID: modID,
            automationID: automationID,
            nextRunAt: nextRunAt,
            lastRunAt: lastRunAt,
            lastStatus: lastStatus,
            lastError: lastError,
            launchdLabel: launchdLabel
        )
    }
}

public final class SQLiteExtensionAutomationStateRepository: ExtensionAutomationStateRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func list(modID: String) async throws -> [ExtensionAutomationStateRecord] {
        try await dbQueue.read { db in
            try ExtensionAutomationStateEntity
                .filter(Column("modID") == modID)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func upsert(_ record: ExtensionAutomationStateRecord) async throws -> ExtensionAutomationStateRecord {
        try await dbQueue.write { db in
            let entity = ExtensionAutomationStateEntity(record: record)
            try entity.save(db)
            return entity.record
        }
    }
}
