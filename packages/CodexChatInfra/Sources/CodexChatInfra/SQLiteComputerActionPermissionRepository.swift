import CodexChatCore
import Foundation
import GRDB

private struct ComputerActionPermissionEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "computer_action_permissions"

    var actionID: String
    var projectKey: String
    var projectID: String?
    var decision: String
    var decidedAt: Date

    init(record: ComputerActionPermissionRecord) {
        actionID = record.actionID
        projectID = record.projectID?.uuidString
        projectKey = Self.projectKey(for: record.projectID)
        decision = record.decision.rawValue
        decidedAt = record.decidedAt
    }

    var record: ComputerActionPermissionRecord {
        ComputerActionPermissionRecord(
            actionID: actionID,
            projectID: UUID(uuidString: projectID ?? ""),
            decision: ComputerActionPermissionDecision(rawValue: decision) ?? .denied,
            decidedAt: decidedAt
        )
    }

    static func projectKey(for projectID: UUID?) -> String {
        projectID?.uuidString.lowercased() ?? "global"
    }
}

public final class SQLiteComputerActionPermissionRepository: ComputerActionPermissionRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func list(projectID: UUID?) async throws -> [ComputerActionPermissionRecord] {
        let projectKey = ComputerActionPermissionEntity.projectKey(for: projectID)
        return try await dbQueue.read { db in
            try ComputerActionPermissionEntity
                .filter(Column("projectKey") == projectKey)
                .order(Column("actionID").asc)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func get(actionID: String, projectID: UUID?) async throws -> ComputerActionPermissionRecord? {
        let projectKey = ComputerActionPermissionEntity.projectKey(for: projectID)
        return try await dbQueue.read { db in
            try ComputerActionPermissionEntity
                .filter(Column("actionID") == actionID)
                .filter(Column("projectKey") == projectKey)
                .fetchOne(db)?
                .record
        }
    }

    public func set(
        actionID: String,
        projectID: UUID?,
        decision: ComputerActionPermissionDecision,
        decidedAt: Date
    ) async throws -> ComputerActionPermissionRecord {
        try await dbQueue.write { db in
            let record = ComputerActionPermissionRecord(
                actionID: actionID,
                projectID: projectID,
                decision: decision,
                decidedAt: decidedAt
            )
            let entity = ComputerActionPermissionEntity(record: record)
            try entity.save(db)
            return entity.record
        }
    }
}
