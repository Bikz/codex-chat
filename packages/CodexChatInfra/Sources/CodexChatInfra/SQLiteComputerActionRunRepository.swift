import CodexChatCore
import Foundation
import GRDB

private struct ComputerActionRunEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "computer_action_runs"

    var id: String
    var actionID: String
    var runContextID: String
    var threadID: String?
    var projectID: String?
    var phase: String
    var status: String
    var previewArtifact: String?
    var summary: String?
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date

    init(record: ComputerActionRunRecord) {
        id = record.id.uuidString
        actionID = record.actionID
        runContextID = record.runContextID
        threadID = record.threadID?.uuidString
        projectID = record.projectID?.uuidString
        phase = record.phase.rawValue
        status = record.status.rawValue
        previewArtifact = record.previewArtifact
        summary = record.summary
        errorMessage = record.errorMessage
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    var record: ComputerActionRunRecord {
        ComputerActionRunRecord(
            id: UUID(uuidString: id) ?? UUID(),
            actionID: actionID,
            runContextID: runContextID,
            threadID: UUID(uuidString: threadID ?? ""),
            projectID: UUID(uuidString: projectID ?? ""),
            phase: ComputerActionRunPhase(rawValue: phase) ?? .preview,
            status: ComputerActionRunStatus(rawValue: status) ?? .failed,
            previewArtifact: previewArtifact,
            summary: summary,
            errorMessage: errorMessage,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public final class SQLiteComputerActionRunRepository: ComputerActionRunRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func list(threadID: UUID?) async throws -> [ComputerActionRunRecord] {
        try await dbQueue.read { db in
            var request = ComputerActionRunEntity
                .order(Column("updatedAt").desc)
                .order(Column("createdAt").desc)

            if let threadID {
                request = request.filter(Column("threadID") == threadID.uuidString)
            }

            return try request.fetchAll(db).map(\.record)
        }
    }

    public func list(runContextID: String) async throws -> [ComputerActionRunRecord] {
        try await dbQueue.read { db in
            try ComputerActionRunEntity
                .filter(Column("runContextID") == runContextID)
                .order(Column("updatedAt").asc)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func upsert(_ record: ComputerActionRunRecord) async throws -> ComputerActionRunRecord {
        try await dbQueue.write { db in
            let entity = ComputerActionRunEntity(record: record)
            try entity.save(db)
            return entity.record
        }
    }

    public func latest(runContextID: String) async throws -> ComputerActionRunRecord? {
        try await dbQueue.read { db in
            try ComputerActionRunEntity
                .filter(Column("runContextID") == runContextID)
                .order(Column("updatedAt").desc)
                .order(Column("createdAt").desc)
                .fetchOne(db)?
                .record
        }
    }
}
