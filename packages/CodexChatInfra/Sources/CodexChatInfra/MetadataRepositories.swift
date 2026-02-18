import CodexChatCore
import Foundation
import GRDB

public struct MetadataRepositories: Sendable {
    public let projectRepository: any ProjectRepository
    public let threadRepository: any ThreadRepository
    public let preferenceRepository: any PreferenceRepository
    public let runtimeThreadMappingRepository: any RuntimeThreadMappingRepository
    public let projectSecretRepository: any ProjectSecretRepository
    public let chatSearchRepository: any ChatSearchRepository

    public init(database: MetadataDatabase) {
        self.projectRepository = SQLiteProjectRepository(dbQueue: database.dbQueue)
        self.threadRepository = SQLiteThreadRepository(dbQueue: database.dbQueue)
        self.preferenceRepository = SQLitePreferenceRepository(dbQueue: database.dbQueue)
        self.runtimeThreadMappingRepository = SQLiteRuntimeThreadMappingRepository(dbQueue: database.dbQueue)
        self.projectSecretRepository = SQLiteProjectSecretRepository(dbQueue: database.dbQueue)
        self.chatSearchRepository = SQLiteChatSearchRepository(dbQueue: database.dbQueue)
    }
}

private struct ProjectEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"

    var id: String
    var name: String
    var path: String
    var trustState: String
    var createdAt: Date
    var updatedAt: Date

    init(record: ProjectRecord) {
        self.id = record.id.uuidString
        self.name = record.name
        self.path = record.path
        self.trustState = record.trustState.rawValue
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
    }

    var record: ProjectRecord {
        ProjectRecord(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            path: path,
            trustState: ProjectTrustState(rawValue: trustState) ?? .untrusted,
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

private struct RuntimeThreadMappingEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "runtime_thread_mappings"

    var localThreadID: String
    var runtimeThreadID: String
    var updatedAt: Date

    init(record: RuntimeThreadMappingRecord) {
        self.localThreadID = record.localThreadID.uuidString
        self.runtimeThreadID = record.runtimeThreadID
        self.updatedAt = record.updatedAt
    }

    var record: RuntimeThreadMappingRecord {
        RuntimeThreadMappingRecord(
            localThreadID: UUID(uuidString: localThreadID) ?? UUID(),
            runtimeThreadID: runtimeThreadID,
            updatedAt: updatedAt
        )
    }
}

private struct ProjectSecretEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project_secrets"

    var id: String
    var projectID: String
    var name: String
    var keychainAccount: String
    var createdAt: Date
    var updatedAt: Date

    init(record: ProjectSecretRecord) {
        self.id = record.id.uuidString
        self.projectID = record.projectID.uuidString
        self.name = record.name
        self.keychainAccount = record.keychainAccount
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
    }

    var record: ProjectSecretRecord {
        ProjectSecretRecord(
            id: UUID(uuidString: id) ?? UUID(),
            projectID: UUID(uuidString: projectID) ?? UUID(),
            name: name,
            keychainAccount: keychainAccount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
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

    public func getProject(path: String) async throws -> ProjectRecord? {
        try await dbQueue.read { db in
            try ProjectEntity
                .filter(Column("path") == path)
                .fetchOne(db)?
                .record
        }
    }

    public func createProject(named name: String, path: String, trustState: ProjectTrustState) async throws -> ProjectRecord {
        try await dbQueue.write { db in
            let now = Date()
            let entity = ProjectEntity(
                record: ProjectRecord(
                    name: name,
                    path: path,
                    trustState: trustState,
                    createdAt: now,
                    updatedAt: now
                )
            )
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

    public func updateProjectTrustState(id: UUID, trustState: ProjectTrustState) async throws -> ProjectRecord {
        try await dbQueue.write { db in
            guard var entity = try ProjectEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }
            entity.trustState = trustState.rawValue
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
}

public final class SQLiteProjectSecretRepository: ProjectSecretRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func listSecrets(projectID: UUID) async throws -> [ProjectSecretRecord] {
        try await dbQueue.read { db in
            try ProjectSecretEntity
                .filter(Column("projectID") == projectID.uuidString)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func upsertSecret(projectID: UUID, name: String, keychainAccount: String) async throws -> ProjectSecretRecord {
        try await dbQueue.write { db in
            let now = Date()
            if var existing = try ProjectSecretEntity
                .filter(Column("projectID") == projectID.uuidString && Column("name") == name)
                .fetchOne(db) {
                existing.keychainAccount = keychainAccount
                existing.updatedAt = now
                try existing.update(db)
                return existing.record
            }

            let entity = ProjectSecretEntity(
                record: ProjectSecretRecord(
                    projectID: projectID,
                    name: name,
                    keychainAccount: keychainAccount,
                    createdAt: now,
                    updatedAt: now
                )
            )
            try entity.insert(db)
            return entity.record
        }
    }

    public func deleteSecret(id: UUID) async throws {
        try await dbQueue.write { db in
            _ = try ProjectSecretEntity.deleteOne(db, key: ["id": id.uuidString])
        }
    }
}

public final class SQLiteChatSearchRepository: ChatSearchRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func indexThreadTitle(threadID: UUID, projectID: UUID, title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM chat_search_index WHERE threadID = ? AND source = 'title'",
                arguments: [threadID.uuidString]
            )
            try db.execute(
                sql: """
                    INSERT INTO chat_search_index(threadID, projectID, source, content)
                    VALUES (?, ?, 'title', ?)
                    """,
                arguments: [threadID.uuidString, projectID.uuidString, trimmed]
            )
        }
    }

    public func indexMessageExcerpt(threadID: UUID, projectID: UUID, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO chat_search_index(threadID, projectID, source, content)
                    VALUES (?, ?, 'message', ?)
                    """,
                arguments: [threadID.uuidString, projectID.uuidString, trimmed]
            )
        }
    }

    public func search(query: String, projectID: UUID?, limit: Int) async throws -> [ChatSearchResult] {
        let normalizedQuery = Self.makeFTSQuery(from: query)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        return try await dbQueue.read { db in
            var sql = """
                SELECT threadID, projectID, source, snippet(chat_search_index, 3, '', '', ' … ', 18) AS excerpt
                FROM chat_search_index
                WHERE chat_search_index MATCH ?
                """
            var arguments: StatementArguments = [normalizedQuery]

            if let projectID {
                sql += " AND projectID = ?"
                arguments += [projectID.uuidString]
            }

            sql += " ORDER BY bm25(chat_search_index) LIMIT ?"
            arguments += [limit]

            return try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap { row in
                guard let threadIDString: String = row["threadID"],
                      let projectIDString: String = row["projectID"],
                      let threadUUID = UUID(uuidString: threadIDString),
                      let projectUUID = UUID(uuidString: projectIDString) else {
                    return nil
                }

                let source: String = row["source"] ?? "message"
                let excerpt: String = row["excerpt"] ?? ""
                return ChatSearchResult(
                    threadID: threadUUID,
                    projectID: projectUUID,
                    source: source,
                    excerpt: excerpt
                )
            }
        }
    }

    private static func makeFTSQuery(from query: String) -> String {
        let tokens = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return ""
        }

        return tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }
}
