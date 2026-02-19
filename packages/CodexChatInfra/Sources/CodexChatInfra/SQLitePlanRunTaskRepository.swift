import CodexChatCore
import Foundation
import GRDB

private struct PlanRunTaskEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "plan_run_tasks"

    var planRunID: String
    var taskID: String
    var title: String
    var dependencyIDs: String
    var status: String
    var updatedAt: Date

    init(record: PlanRunTaskRecord) {
        planRunID = record.planRunID.uuidString
        taskID = record.taskID
        title = record.title
        dependencyIDs = Self.encodeDependencies(record.dependencyIDs)
        status = record.status.rawValue
        updatedAt = record.updatedAt
    }

    var record: PlanRunTaskRecord {
        PlanRunTaskRecord(
            planRunID: UUID(uuidString: planRunID) ?? UUID(),
            taskID: taskID,
            title: title,
            dependencyIDs: Self.decodeDependencies(dependencyIDs),
            status: PlanTaskRunStatus(rawValue: status) ?? .failed,
            updatedAt: updatedAt
        )
    }

    private static func encodeDependencies(_ values: [String]) -> String {
        if let data = try? JSONEncoder().encode(values),
           let text = String(data: data, encoding: .utf8)
        {
            return text
        }
        return "[]"
    }

    private static func decodeDependencies(_ text: String) -> [String] {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return decoded
    }
}

public final class SQLitePlanRunTaskRepository: PlanRunTaskRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func list(planRunID: UUID) async throws -> [PlanRunTaskRecord] {
        try await dbQueue.read { db in
            try PlanRunTaskEntity
                .filter(Column("planRunID") == planRunID.uuidString)
                .order(Column("taskID").asc)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func upsert(_ record: PlanRunTaskRecord) async throws -> PlanRunTaskRecord {
        try await dbQueue.write { db in
            let entity = PlanRunTaskEntity(record: record)
            try entity.save(db)
            return entity.record
        }
    }

    public func replace(planRunID: UUID, tasks: [PlanRunTaskRecord]) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM plan_run_tasks WHERE planRunID = ?",
                arguments: [planRunID.uuidString]
            )

            for task in tasks {
                let entity = PlanRunTaskEntity(record: task)
                try entity.insert(db)
            }
        }
    }
}
