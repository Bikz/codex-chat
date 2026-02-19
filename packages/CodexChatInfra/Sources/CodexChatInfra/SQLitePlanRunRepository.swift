import CodexChatCore
import Foundation
import GRDB

private struct PlanRunEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "plan_runs"

    var id: String
    var threadID: String
    var projectID: String
    var title: String
    var sourcePath: String?
    var status: String
    var totalTasks: Int
    var completedTasks: Int
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    init(record: PlanRunRecord) {
        id = record.id.uuidString
        threadID = record.threadID.uuidString
        projectID = record.projectID.uuidString
        title = record.title
        sourcePath = record.sourcePath
        status = record.status.rawValue
        totalTasks = record.totalTasks
        completedTasks = record.completedTasks
        lastError = record.lastError
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    var record: PlanRunRecord {
        PlanRunRecord(
            id: UUID(uuidString: id) ?? UUID(),
            threadID: UUID(uuidString: threadID) ?? UUID(),
            projectID: UUID(uuidString: projectID) ?? UUID(),
            title: title,
            sourcePath: sourcePath,
            status: PlanRunStatus(rawValue: status) ?? .failed,
            totalTasks: totalTasks,
            completedTasks: completedTasks,
            lastError: lastError,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public final class SQLitePlanRunRepository: PlanRunRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func list(threadID: UUID) async throws -> [PlanRunRecord] {
        try await dbQueue.read { db in
            try PlanRunEntity
                .filter(Column("threadID") == threadID.uuidString)
                .order(Column("updatedAt").desc)
                .order(Column("createdAt").desc)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func get(id: UUID) async throws -> PlanRunRecord? {
        try await dbQueue.read { db in
            try PlanRunEntity.fetchOne(db, key: ["id": id.uuidString])?.record
        }
    }

    public func upsert(_ record: PlanRunRecord) async throws -> PlanRunRecord {
        try await dbQueue.write { db in
            let entity = PlanRunEntity(record: record)
            try entity.save(db)
            return entity.record
        }
    }

    public func delete(id: UUID) async throws {
        try await dbQueue.write { db in
            _ = try PlanRunEntity.deleteOne(db, key: ["id": id.uuidString])
        }
    }
}
