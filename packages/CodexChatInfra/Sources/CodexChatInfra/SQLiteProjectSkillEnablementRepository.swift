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

private struct SkillEnablementEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "skill_enablements"

    var target: String
    var projectID: String?
    var skillPath: String
    var enabled: Bool
    var updatedAt: Date
}

public final class SQLiteProjectSkillEnablementRepository: ProjectSkillEnablementRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func setSkillEnabled(target: SkillEnablementTarget, projectID: UUID?, skillPath: String, enabled: Bool) async throws {
        let normalizedPath = normalized(skillPath: skillPath)
        guard !normalizedPath.isEmpty else { return }
        try validateTargetScope(target: target, projectID: projectID)

        try await dbQueue.write { db in
            try upsertSkillEnablement(
                db: db,
                target: target.rawValue,
                projectID: projectID?.uuidString,
                skillPath: normalizedPath,
                enabled: enabled,
                updatedAt: Date()
            )
        }
    }

    public func isSkillEnabled(target: SkillEnablementTarget, projectID: UUID?, skillPath: String) async throws -> Bool {
        let normalizedPath = normalized(skillPath: skillPath)
        guard !normalizedPath.isEmpty else { return false }
        try validateTargetScope(target: target, projectID: projectID)

        let targetValue = target.rawValue
        let projectIDValue = projectID?.uuidString

        return try await dbQueue.read { db in
            if let value = try Bool.fetchOne(
                db,
                sql: """
                SELECT enabled
                FROM skill_enablements
                WHERE target = ? AND IFNULL(projectID, '') = IFNULL(?, '') AND skillPath = ?
                ORDER BY updatedAt DESC
                LIMIT 1
                """,
                arguments: [targetValue, projectIDValue, normalizedPath]
            ) {
                return value
            }

            guard target == .project, let projectIDValue else {
                return false
            }

            let legacy = try ProjectSkillEnablementEntity.fetchOne(
                db,
                key: ["projectID": projectIDValue, "skillPath": normalizedPath]
            )
            return legacy?.enabled ?? false
        }
    }

    public func enabledSkillPaths(target: SkillEnablementTarget, projectID: UUID?) async throws -> Set<String> {
        try validateTargetScope(target: target, projectID: projectID)
        let targetValue = target.rawValue
        let projectIDValue = projectID?.uuidString

        return try await dbQueue.read { db in
            let newPaths = try String.fetchAll(
                db,
                sql: """
                SELECT skillPath
                FROM skill_enablements
                WHERE target = ? AND IFNULL(projectID, '') = IFNULL(?, '') AND enabled = 1
                """,
                arguments: [targetValue, projectIDValue]
            )
            if !newPaths.isEmpty {
                return Set(newPaths)
            }

            let hasNewRows = try (Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM skill_enablements
                WHERE target = ? AND IFNULL(projectID, '') = IFNULL(?, '')
                """,
                arguments: [targetValue, projectIDValue]
            ) ?? 0) > 0

            if hasNewRows || target != .project || projectIDValue == nil {
                return Set(newPaths)
            }

            let legacy = try ProjectSkillEnablementEntity
                .filter(Column("projectID") == projectIDValue! && Column("enabled") == true)
                .fetchAll(db)
            return Set(legacy.map(\.skillPath))
        }
    }

    public func resolvedEnabledSkillPaths(forProjectID projectID: UUID?, generalProjectID _: UUID?) async throws -> Set<String> {
        var resolved = try await enabledSkillPaths(target: .global, projectID: nil)
        try await resolved.formUnion(enabledSkillPaths(target: .general, projectID: nil))
        if let projectID {
            try await resolved.formUnion(enabledSkillPaths(target: .project, projectID: projectID))
        }
        return resolved
    }

    public func rewriteSkillPaths(fromRootPath: String, toRootPath: String) async throws {
        let normalizedFrom = normalizedRoot(fromRootPath)
        let normalizedTo = normalizedRoot(toRootPath)
        guard normalizedFrom != normalizedTo else {
            return
        }

        try await dbQueue.write { db in
            try rewriteNewSkillPaths(
                db: db,
                fromRootPath: normalizedFrom,
                toRootPath: normalizedTo,
                target: nil,
                projectID: nil
            )
            try rewriteLegacySkillPaths(
                db: db,
                fromRootPath: normalizedFrom,
                toRootPath: normalizedTo,
                projectID: nil
            )
        }
    }

    public func setSkillEnabled(projectID: UUID, skillPath: String, enabled: Bool) async throws {
        try await setSkillEnabled(target: .project, projectID: projectID, skillPath: skillPath, enabled: enabled)
    }

    public func isSkillEnabled(projectID: UUID, skillPath: String) async throws -> Bool {
        try await isSkillEnabled(target: .project, projectID: projectID, skillPath: skillPath)
    }

    public func enabledSkillPaths(projectID: UUID) async throws -> Set<String> {
        try await enabledSkillPaths(target: .project, projectID: projectID)
    }

    public func rewriteSkillPaths(projectID: UUID, fromRootPath: String, toRootPath: String) async throws {
        let normalizedFrom = normalizedRoot(fromRootPath)
        let normalizedTo = normalizedRoot(toRootPath)
        guard normalizedFrom != normalizedTo else {
            return
        }

        let projectIDValue = projectID.uuidString
        try await dbQueue.write { db in
            try rewriteNewSkillPaths(
                db: db,
                fromRootPath: normalizedFrom,
                toRootPath: normalizedTo,
                target: SkillEnablementTarget.project.rawValue,
                projectID: projectIDValue
            )
            try rewriteLegacySkillPaths(
                db: db,
                fromRootPath: normalizedFrom,
                toRootPath: normalizedTo,
                projectID: projectIDValue
            )
        }
    }

    private func rewriteNewSkillPaths(
        db: Database,
        fromRootPath: String,
        toRootPath: String,
        target: String?,
        projectID: String?
    ) throws {
        let entities: [SkillEnablementEntity] = if let target {
            try SkillEnablementEntity.fetchAll(
                db,
                sql: """
                SELECT target, projectID, skillPath, enabled, updatedAt
                FROM skill_enablements
                WHERE target = ? AND IFNULL(projectID, '') = IFNULL(?, '')
                """,
                arguments: [target, projectID]
            )
        } else {
            try SkillEnablementEntity.fetchAll(
                db,
                sql: "SELECT target, projectID, skillPath, enabled, updatedAt FROM skill_enablements"
            )
        }

        for entity in entities where entity.skillPath.hasPrefix(fromRootPath) {
            let suffix = String(entity.skillPath.dropFirst(fromRootPath.count))
            let rewrittenPath = (toRootPath + suffix).replacingOccurrences(of: "//", with: "/")
            guard rewrittenPath != entity.skillPath else { continue }

            let existingEnabled = try Bool.fetchOne(
                db,
                sql: """
                SELECT enabled
                FROM skill_enablements
                WHERE target = ? AND IFNULL(projectID, '') = IFNULL(?, '') AND skillPath = ?
                ORDER BY updatedAt DESC
                LIMIT 1
                """,
                arguments: [entity.target, entity.projectID, rewrittenPath]
            ) ?? false
            let mergedEnabled = existingEnabled || entity.enabled

            try db.execute(
                sql: """
                DELETE FROM skill_enablements
                WHERE target = ? AND IFNULL(projectID, '') = IFNULL(?, '') AND skillPath = ?
                """,
                arguments: [entity.target, entity.projectID, entity.skillPath]
            )

            try upsertSkillEnablement(
                db: db,
                target: entity.target,
                projectID: entity.projectID,
                skillPath: rewrittenPath,
                enabled: mergedEnabled,
                updatedAt: Date()
            )
        }
    }

    private func rewriteLegacySkillPaths(
        db: Database,
        fromRootPath: String,
        toRootPath: String,
        projectID: String?
    ) throws {
        let entities: [ProjectSkillEnablementEntity] = if let projectID {
            try ProjectSkillEnablementEntity
                .filter(Column("projectID") == projectID)
                .fetchAll(db)
        } else {
            try ProjectSkillEnablementEntity.fetchAll(db)
        }

        for entity in entities where entity.skillPath.hasPrefix(fromRootPath) {
            let suffix = String(entity.skillPath.dropFirst(fromRootPath.count))
            let rewrittenPath = (toRootPath + suffix).replacingOccurrences(of: "//", with: "/")
            guard rewrittenPath != entity.skillPath else { continue }

            var destinationEntity = try ProjectSkillEnablementEntity.fetchOne(
                db,
                key: ["projectID": entity.projectID, "skillPath": rewrittenPath]
            )

            if destinationEntity == nil {
                destinationEntity = ProjectSkillEnablementEntity(
                    record: ProjectSkillEnablementRecord(
                        projectID: UUID(uuidString: entity.projectID) ?? UUID(),
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
                arguments: [entity.projectID, entity.skillPath]
            )
            if let destinationEntity {
                try destinationEntity.save(db)
            }
        }
    }

    private func upsertSkillEnablement(
        db: Database,
        target: String,
        projectID: String?,
        skillPath: String,
        enabled: Bool,
        updatedAt: Date
    ) throws {
        try db.execute(
            sql: """
            DELETE FROM skill_enablements
            WHERE target = ? AND IFNULL(projectID, '') = IFNULL(?, '') AND skillPath = ?
            """,
            arguments: [target, projectID, skillPath]
        )
        try SkillEnablementEntity(
            target: target,
            projectID: projectID,
            skillPath: skillPath,
            enabled: enabled,
            updatedAt: updatedAt
        ).insert(db)
    }

    private func normalized(skillPath: String) -> String {
        skillPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedRoot(_ rootPath: String) -> String {
        URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
    }

    private func validateTargetScope(target: SkillEnablementTarget, projectID: UUID?) throws {
        guard target != .project || projectID != nil else {
            throw NSError(
                domain: "CodexChatInfra.SkillEnablement",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Project target requires a project identifier."]
            )
        }
    }
}
