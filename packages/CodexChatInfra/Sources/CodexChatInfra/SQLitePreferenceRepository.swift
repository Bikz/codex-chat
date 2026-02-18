import CodexChatCore
import Foundation
import GRDB

private struct PreferenceEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "preferences"

    var key: String
    var value: String
}

public final class SQLitePreferenceRepository: PreferenceRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func setPreference(key: AppPreferenceKey, value: String) async throws {
        try await dbQueue.write { db in
            let entity = PreferenceEntity(key: key.rawValue, value: value)
            try entity.save(db)
        }
    }

    public func getPreference(key: AppPreferenceKey) async throws -> String? {
        try await dbQueue.read { db in
            try PreferenceEntity.fetchOne(db, key: ["key": key.rawValue])?.value
        }
    }
}
