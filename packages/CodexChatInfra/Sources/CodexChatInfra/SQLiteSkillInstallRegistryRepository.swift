import CodexChatCore
import Foundation
import GRDB

private struct SkillInstallEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "skill_installs"

    var skillID: String
    var source: String
    var installer: String
    var sharedPath: String
    var mode: String
    var projectIDs: String?
    var createdAt: Date
    var updatedAt: Date

    init(record: SkillInstallRecord) {
        skillID = record.skillID
        source = record.source
        installer = record.installer.rawValue
        sharedPath = record.sharedPath
        mode = record.mode.rawValue
        projectIDs = Self.encode(projectIDs: record.projectIDs)
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    var record: SkillInstallRecord {
        SkillInstallRecord(
            skillID: skillID,
            source: source,
            installer: SkillInstallMethod(rawValue: installer) ?? .git,
            sharedPath: sharedPath,
            mode: SkillInstallMode(rawValue: mode) ?? .selected,
            projectIDs: Self.decode(projectIDs: projectIDs),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func encode(projectIDs: [UUID]) -> String? {
        guard !projectIDs.isEmpty else {
            return nil
        }

        let values = projectIDs.map(\.uuidString)
        guard let data = try? JSONEncoder().encode(values) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func decode(projectIDs: String?) -> [UUID] {
        guard let projectIDs,
              let data = projectIDs.data(using: .utf8),
              let encoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return encoded.compactMap(UUID.init(uuidString:))
    }
}

public final class SQLiteSkillInstallRegistryRepository: SkillInstallRegistryRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func list() async throws -> [SkillInstallRecord] {
        try await dbQueue.read { db in
            try SkillInstallEntity
                .order(Column("updatedAt").desc)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func get(skillID: String) async throws -> SkillInstallRecord? {
        let normalizedID = Self.normalizedSkillID(skillID)
        guard !normalizedID.isEmpty else {
            return nil
        }

        return try await dbQueue.read { db in
            try SkillInstallEntity.fetchOne(db, key: ["skillID": normalizedID])?.record
        }
    }

    public func upsert(_ record: SkillInstallRecord) async throws -> SkillInstallRecord {
        let normalizedID = Self.normalizedSkillID(record.skillID)
        guard !normalizedID.isEmpty else {
            throw DatabaseError(message: "Skill install id must not be empty.")
        }

        let persisted = SkillInstallRecord(
            skillID: normalizedID,
            source: record.source.trimmingCharacters(in: .whitespacesAndNewlines),
            installer: record.installer,
            sharedPath: record.sharedPath,
            mode: record.mode,
            projectIDs: Array(Set(record.projectIDs)).sorted(by: { $0.uuidString < $1.uuidString }),
            createdAt: record.createdAt,
            updatedAt: Date()
        )

        return try await dbQueue.write { db in
            try SkillInstallEntity(record: persisted).save(db)
            return persisted
        }
    }

    public func delete(skillID: String) async throws {
        let normalizedID = Self.normalizedSkillID(skillID)
        guard !normalizedID.isEmpty else {
            return
        }

        try await dbQueue.write { db in
            _ = try SkillInstallEntity.deleteOne(db, key: ["skillID": normalizedID])
        }
    }

    public func listInstalledSkillIDs(forProjectID projectID: UUID) async throws -> Set<String> {
        let projectKey = projectID.uuidString.lowercased()
        let records = try await list()

        return Set(records.compactMap { record in
            switch record.mode {
            case .all:
                record.skillID
            case .selected:
                record.projectIDs.contains(where: { $0.uuidString.lowercased() == projectKey })
                    ? record.skillID
                    : nil
            }
        })
    }

    private static func normalizedSkillID(_ skillID: String) -> String {
        skillID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
