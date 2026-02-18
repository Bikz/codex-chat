import CodexChatCore
import Foundation
import GRDB

private struct ThreadEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "threads"

    var id: String
    var projectId: String
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(record: ThreadRecord) {
        id = record.id.uuidString
        projectId = record.projectId.uuidString
        title = record.title
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    var record: ThreadRecord {
        ThreadRecord(
            id: UUID(uuidString: id) ?? UUID(),
            projectId: UUID(uuidString: projectId) ?? UUID(),
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public final class SQLiteThreadRepository: ThreadRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func listThreads(projectID: UUID) async throws -> [ThreadRecord] {
        try await dbQueue.read { db in
            try ThreadEntity
                .filter(Column("projectId") == projectID.uuidString)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func getThread(id: UUID) async throws -> ThreadRecord? {
        try await dbQueue.read { db in
            try ThreadEntity.fetchOne(db, key: ["id": id.uuidString])?.record
        }
    }

    public func createThread(projectID: UUID, title: String) async throws -> ThreadRecord {
        try await dbQueue.write { db in
            let now = Date()
            let entity = ThreadEntity(
                record: ThreadRecord(projectId: projectID, title: title, createdAt: now, updatedAt: now)
            )
            try entity.insert(db)
            return entity.record
        }
    }

    public func updateThreadTitle(id: UUID, title: String) async throws -> ThreadRecord {
        try await dbQueue.write { db in
            guard var entity = try ThreadEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }
            entity.title = title
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
    }
}
