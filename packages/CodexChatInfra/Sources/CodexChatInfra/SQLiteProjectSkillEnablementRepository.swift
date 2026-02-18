import CodexChatCore
import Foundation
import GRDB

private struct ProjectSkillEnablementEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project_skill_enablements"

    var projectID: String
    var skillPath: String
    var enabled: Bool
    var updatedAt: Date

    init(record: ProjectSkillEnablementRecord) {
        projectID = record.projectID.uuidString
        skillPath = record.skillPath
        enabled = record.enabled
        updatedAt = record.updatedAt
    }

    var record: ProjectSkillEnablementRecord {
        ProjectSkillEnablementRecord(
            projectID: UUID(uuidString: projectID) ?? UUID(),
            skillPath: skillPath,
            enabled: enabled,
            updatedAt: updatedAt
        )
    }
}

public final class SQLiteProjectSkillEnablementRepository: ProjectSkillEnablementRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func setSkillEnabled(projectID: UUID, skillPath: String, enabled: Bool) async throws {
        let normalizedPath = skillPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else { return }

        try await dbQueue.write { db in
            let entity = ProjectSkillEnablementEntity(
                record: ProjectSkillEnablementRecord(
                    projectID: projectID,
                    skillPath: normalizedPath,
                    enabled: enabled,
                    updatedAt: Date()
                )
            )
            try entity.save(db)
        }
    }

    public func isSkillEnabled(projectID: UUID, skillPath: String) async throws -> Bool {
        let normalizedPath = skillPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else { return false }

        return try await dbQueue.read { db in
            let entity = try ProjectSkillEnablementEntity.fetchOne(
                db,
                key: ["projectID": projectID.uuidString, "skillPath": normalizedPath]
            )
            return entity?.enabled ?? false
        }
    }

    public func enabledSkillPaths(projectID: UUID) async throws -> Set<String> {
        try await dbQueue.read { db in
            let entities = try ProjectSkillEnablementEntity
                .filter(Column("projectID") == projectID.uuidString && Column("enabled") == true)
                .fetchAll(db)
            return Set(entities.map(\.skillPath))
        }
    }

    public func rewriteSkillPaths(projectID: UUID, fromRootPath: String, toRootPath: String) async throws {
        let normalizedFrom = URL(fileURLWithPath: fromRootPath, isDirectory: true).standardizedFileURL.path
        let normalizedTo = URL(fileURLWithPath: toRootPath, isDirectory: true).standardizedFileURL.path

        guard normalizedFrom != normalizedTo else {
            return
        }

        try await dbQueue.write { db in
            let projectIDString = projectID.uuidString
            let entities = try ProjectSkillEnablementEntity
                .filter(Column("projectID") == projectIDString)
                .fetchAll(db)

            for entity in entities where entity.skillPath.hasPrefix(normalizedFrom) {
                let suffix = String(entity.skillPath.dropFirst(normalizedFrom.count))
                let rewrittenPath = (normalizedTo + suffix).replacingOccurrences(of: "//", with: "/")
                guard rewrittenPath != entity.skillPath else { continue }

                var destinationEntity = try ProjectSkillEnablementEntity.fetchOne(
                    db,
                    key: ["projectID": projectIDString, "skillPath": rewrittenPath]
                )

                if destinationEntity == nil {
                    destinationEntity = ProjectSkillEnablementEntity(
                        record: ProjectSkillEnablementRecord(
                            projectID: projectID,
                            skillPath: rewrittenPath,
                            enabled: entity.enabled,
                            updatedAt: Date()
                        )
                    )
                } else if var existing = destinationEntity {
                    existing.enabled = existing.enabled || entity.enabled
                    existing.updatedAt = Date()
                    destinationEntity = existing
                }

                try db.execute(
                    sql: """
                    DELETE FROM project_skill_enablements
                    WHERE projectID = ? AND skillPath = ?
                    """,
                    arguments: [projectIDString, entity.skillPath]
                )
                if let destinationEntity {
                    try destinationEntity.save(db)
                }
            }
        }
    }
}
