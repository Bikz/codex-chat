import CodexChatCore
import Foundation
import GRDB

public struct MetadataRepositories: Sendable {
    public let projectRepository: any ProjectRepository
    public let threadRepository: any ThreadRepository
    public let preferenceRepository: any PreferenceRepository

    public init(database: MetadataDatabase) {
        self.projectRepository = SQLiteProjectRepository(dbQueue: database.dbQueue)
        self.threadRepository = SQLiteThreadRepository(dbQueue: database.dbQueue)
        self.preferenceRepository = SQLitePreferenceRepository(dbQueue: database.dbQueue)
    }
}

private struct ProjectEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"

    var id: String
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(record: ProjectRecord) {
        self.id = record.id.uuidString
        self.name = record.name
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
    }

    var record: ProjectRecord {
        ProjectRecord(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct ThreadEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "threads"

    var id: String
    var projectId: String
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(record: ThreadRecord) {
        self.id = record.id.uuidString
        self.projectId = record.projectId.uuidString
        self.title = record.title
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
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

private struct PreferenceEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "preferences"

    var key: String
    var value: String
}

public final class SQLiteProjectRepository: ProjectRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func listProjects() async throws -> [ProjectRecord] {
        try await dbQueue.read { db in
            try ProjectEntity
                .order(Column("updatedAt").desc)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func getProject(id: UUID) async throws -> ProjectRecord? {
        try await dbQueue.read { db in
            try ProjectEntity.fetchOne(db, key: ["id": id.uuidString])?.record
        }
    }

    public func createProject(named name: String) async throws -> ProjectRecord {
        try await dbQueue.write { db in
            let now = Date()
            let entity = ProjectEntity(record: ProjectRecord(name: name, createdAt: now, updatedAt: now))
            try entity.insert(db)
            return entity.record
        }
    }

    public func updateProjectName(id: UUID, name: String) async throws -> ProjectRecord {
        try await dbQueue.write { db in
            guard var entity = try ProjectEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }
            entity.name = name
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
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
