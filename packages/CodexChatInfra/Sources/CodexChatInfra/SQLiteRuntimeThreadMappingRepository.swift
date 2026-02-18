import CodexChatCore
import Foundation
import GRDB

private struct RuntimeThreadMappingEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "runtime_thread_mappings"

    var localThreadID: String
    var runtimeThreadID: String
    var updatedAt: Date

    init(record: RuntimeThreadMappingRecord) {
        localThreadID = record.localThreadID.uuidString
        runtimeThreadID = record.runtimeThreadID
        updatedAt = record.updatedAt
    }

    var record: RuntimeThreadMappingRecord {
        RuntimeThreadMappingRecord(
            localThreadID: UUID(uuidString: localThreadID) ?? UUID(),
            runtimeThreadID: runtimeThreadID,
            updatedAt: updatedAt
        )
    }
}

public final class SQLiteRuntimeThreadMappingRepository: RuntimeThreadMappingRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func setRuntimeThreadID(localThreadID: UUID, runtimeThreadID: String) async throws {
        try await dbQueue.write { db in
            let entity = RuntimeThreadMappingEntity(
                record: RuntimeThreadMappingRecord(
                    localThreadID: localThreadID,
                    runtimeThreadID: runtimeThreadID,
                    updatedAt: Date()
                )
            )
            try entity.save(db)
        }
    }

    public func getRuntimeThreadID(localThreadID: UUID) async throws -> String? {
        try await dbQueue.read { db in
            try RuntimeThreadMappingEntity.fetchOne(db, key: ["localThreadID": localThreadID.uuidString])?.runtimeThreadID
        }
    }

    public func getLocalThreadID(runtimeThreadID: String) async throws -> UUID? {
        try await dbQueue.read { db in
            try RuntimeThreadMappingEntity
                .filter(Column("runtimeThreadID") == runtimeThreadID)
                .fetchOne(db)
                .flatMap { UUID(uuidString: $0.localThreadID) }
        }
    }
}
