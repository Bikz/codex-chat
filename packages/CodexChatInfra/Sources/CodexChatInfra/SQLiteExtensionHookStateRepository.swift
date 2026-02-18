import CodexChatCore
import Foundation
import GRDB

private struct ExtensionHookStateEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "extension_hook_state"

    var modID: String
    var hookID: String
    var lastRunAt: Date?
    var lastStatus: String
    var lastError: String?

    init(record: ExtensionHookStateRecord) {
        modID = record.modID
        hookID = record.hookID
        lastRunAt = record.lastRunAt
        lastStatus = record.lastStatus
        lastError = record.lastError
    }

    var record: ExtensionHookStateRecord {
        ExtensionHookStateRecord(
            modID: modID,
            hookID: hookID,
            lastRunAt: lastRunAt,
            lastStatus: lastStatus,
            lastError: lastError
        )
    }
}

public final class SQLiteExtensionHookStateRepository: ExtensionHookStateRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func list(modID: String) async throws -> [ExtensionHookStateRecord] {
        try await dbQueue.read { db in
            try ExtensionHookStateEntity
                .filter(Column("modID") == modID)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func upsert(_ record: ExtensionHookStateRecord) async throws -> ExtensionHookStateRecord {
        try await dbQueue.write { db in
            let entity = ExtensionHookStateEntity(record: record)
            try entity.save(db)
            return entity.record
        }
    }
}
