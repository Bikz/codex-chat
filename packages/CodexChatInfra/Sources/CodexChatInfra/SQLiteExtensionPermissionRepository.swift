import CodexChatCore
import Foundation
import GRDB

private struct ExtensionPermissionEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "extension_permissions"

    var modID: String
    var permissionKey: String
    var status: String
    var grantedAt: Date

    init(record: ExtensionPermissionRecord) {
        modID = record.modID
        permissionKey = record.permissionKey.rawValue
        status = record.status.rawValue
        grantedAt = record.grantedAt
    }

    var record: ExtensionPermissionRecord {
        ExtensionPermissionRecord(
            modID: modID,
            permissionKey: ExtensionPermissionKey(rawValue: permissionKey) ?? .projectRead,
            status: ExtensionPermissionStatus(rawValue: status) ?? .denied,
            grantedAt: grantedAt
        )
    }
}

public final class SQLiteExtensionPermissionRepository: ExtensionPermissionRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func list(modID: String) async throws -> [ExtensionPermissionRecord] {
        try await dbQueue.read { db in
            try ExtensionPermissionEntity
                .filter(Column("modID") == modID)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func set(
        modID: String,
        permissionKey: ExtensionPermissionKey,
        status: ExtensionPermissionStatus,
        grantedAt: Date
    ) async throws {
        try await dbQueue.write { db in
            let entity = ExtensionPermissionEntity(
                record: ExtensionPermissionRecord(
                    modID: modID,
                    permissionKey: permissionKey,
                    status: status,
                    grantedAt: grantedAt
                )
            )
            try entity.save(db)
        }
    }
}
