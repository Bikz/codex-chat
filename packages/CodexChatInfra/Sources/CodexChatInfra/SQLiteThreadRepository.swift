import CodexChatCore
import Foundation
import GRDB

private struct ThreadEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "threads"

    var id: String
    var projectId: String
    var title: String
    var isPinned: Bool
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(record: ThreadRecord) {
        id = record.id.uuidString
        projectId = record.projectId.uuidString
        title = record.title
        isPinned = record.isPinned
        archivedAt = record.archivedAt
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    var record: ThreadRecord {
        ThreadRecord(
            id: UUID(uuidString: id) ?? UUID(),
            projectId: UUID(uuidString: projectId) ?? UUID(),
            title: title,
            isPinned: isPinned,
            archivedAt: archivedAt,
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

    public func listThreads(projectID: UUID, scope: ThreadListScope) async throws -> [ThreadRecord] {
        try await dbQueue.read { db in
            var request = ThreadEntity
                .filter(Column("projectId") == projectID.uuidString)

            switch scope {
            case .active:
                request = request.filter(Column("archivedAt") == nil)
                    .order(
                        Column("isPinned").desc,
                        Column("updatedAt").desc,
                        Column("createdAt").desc,
                        Column("id").asc
                    )
            case .archived:
                request = request.filter(Column("archivedAt") != nil)
                    .order(
                        Column("archivedAt").desc,
                        Column("updatedAt").desc,
                        Column("createdAt").desc,
                        Column("id").asc
                    )
            case .all:
                request = request
                    .order(
                        Column("isPinned").desc,
                        Column("updatedAt").desc,
                        Column("createdAt").desc,
                        Column("id").asc
                    )
            }

            return try request.fetchAll(db).map(\.record)
        }
    }

    public func listArchivedThreads() async throws -> [ThreadRecord] {
        try await dbQueue.read { db in
            try ThreadEntity
                .filter(Column("archivedAt") != nil)
                .order(
                    Column("archivedAt").desc,
                    Column("updatedAt").desc,
                    Column("createdAt").desc,
                    Column("id").asc
                )
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
                record: ThreadRecord(
                    projectId: projectID,
                    title: title,
                    isPinned: false,
                    archivedAt: nil,
                    createdAt: now,
                    updatedAt: now
                )
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

    public func setThreadPinned(id: UUID, isPinned: Bool) async throws -> ThreadRecord {
        try await dbQueue.write { db in
            guard var entity = try ThreadEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }
            entity.isPinned = entity.archivedAt == nil ? isPinned : false
            try entity.update(db)
            return entity.record
        }
    }

    public func archiveThread(id: UUID, archivedAt: Date) async throws -> ThreadRecord {
        try await dbQueue.write { db in
            guard var entity = try ThreadEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }
            entity.archivedAt = archivedAt
            entity.isPinned = false
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
    }

    public func unarchiveThread(id: UUID) async throws -> ThreadRecord {
        try await dbQueue.write { db in
            guard var entity = try ThreadEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }
            entity.archivedAt = nil
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
    }

    public func touchThread(id: UUID) async throws -> ThreadRecord {
        try await dbQueue.write { db in
            guard var entity = try ThreadEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
    }
}
