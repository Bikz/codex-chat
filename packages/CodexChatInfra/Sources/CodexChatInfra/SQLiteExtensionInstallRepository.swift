import CodexChatCore
import Foundation
import GRDB

private struct ExtensionInstallEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "extension_installs"

    var id: String
    var modID: String
    var scope: String
    var projectID: String?
    var sourceURL: String?
    var installedPath: String
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(record: ExtensionInstallRecord) {
        id = record.id
        modID = record.modID
        scope = record.scope.rawValue
        projectID = record.projectID?.uuidString
        sourceURL = record.sourceURL
        installedPath = record.installedPath
        enabled = record.enabled
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    var record: ExtensionInstallRecord {
        ExtensionInstallRecord(
            id: id,
            modID: modID,
            scope: ExtensionInstallScope(rawValue: scope) ?? .global,
            projectID: projectID.flatMap(UUID.init(uuidString:)),
            sourceURL: sourceURL,
            installedPath: installedPath,
            enabled: enabled,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public final class SQLiteExtensionInstallRepository: ExtensionInstallRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func list() async throws -> [ExtensionInstallRecord] {
        try await dbQueue.read { db in
            try ExtensionInstallEntity
                .order(Column("updatedAt").desc)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func upsert(_ record: ExtensionInstallRecord) async throws -> ExtensionInstallRecord {
        try await dbQueue.write { db in
            var entity = ExtensionInstallEntity(record: record)
            entity.updatedAt = Date()
            if try ExtensionInstallEntity.fetchOne(db, key: ["id": entity.id]) == nil {
                entity.createdAt = entity.updatedAt
            }
            try entity.save(db)
            return entity.record
        }
    }

    public func delete(id: String) async throws {
        try await dbQueue.write { db in
            _ = try ExtensionInstallEntity.deleteOne(db, key: ["id": id])
        }
    }
}
