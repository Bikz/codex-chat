import CodexChatCore
import Foundation
import GRDB

private struct ProjectSecretEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project_secrets"

    var id: String
    var projectID: String
    var name: String
    var keychainAccount: String
    var createdAt: Date
    var updatedAt: Date

    init(record: ProjectSecretRecord) {
        id = record.id.uuidString
        projectID = record.projectID.uuidString
        name = record.name
        keychainAccount = record.keychainAccount
        createdAt = record.createdAt
        updatedAt = record.updatedAt
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
                .fetchOne(db)
            {
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
