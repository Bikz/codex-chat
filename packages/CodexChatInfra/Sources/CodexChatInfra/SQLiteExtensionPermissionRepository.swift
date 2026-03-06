import CodexChatCore
import Foundation
import GRDB

private struct ExtensionPermissionEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "extension_permissions"

    var installID: String
    var modID: String
    var permissionKey: String
    var status: String
    var grantedAt: Date

    init(record: ExtensionPermissionRecord) {
        installID = record.installID
        modID = record.modID
        permissionKey = record.permissionKey.rawValue
        status = record.status.rawValue
        grantedAt = record.grantedAt
    }

    var record: ExtensionPermissionRecord {
        ExtensionPermissionRecord(
            installID: installID,
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

    public func list(installID: String) async throws -> [ExtensionPermissionRecord] {
        try await dbQueue.read { db in
            try ExtensionPermissionEntity
                .filter(Column("installID") == installID)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func set(
        installID: String,
        modID: String,
        permissionKey: ExtensionPermissionKey,
        status: ExtensionPermissionStatus,
        grantedAt: Date
    ) async throws {
        try await dbQueue.write { db in
            let entity = ExtensionPermissionEntity(
                record: ExtensionPermissionRecord(
                    installID: installID,
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
