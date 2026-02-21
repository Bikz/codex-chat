import CodexChatCore
import Foundation
import GRDB

private struct ProjectEntity: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"

    var id: String
    var name: String
    var path: String
    var isGeneralProject: Bool
    var trustState: String
    var sandboxMode: String
    var approvalPolicy: String
    var networkAccess: Bool
    var webSearch: String
    var memoryWriteMode: String
    var memoryEmbeddingsEnabled: Bool
    var uiModPath: String?
    var createdAt: Date
    var updatedAt: Date

    init(record: ProjectRecord) {
        id = record.id.uuidString
        name = record.name
        path = record.path
        isGeneralProject = record.isGeneralProject
        trustState = record.trustState.rawValue
        sandboxMode = record.sandboxMode.rawValue
        approvalPolicy = record.approvalPolicy.rawValue
        networkAccess = record.networkAccess
        webSearch = record.webSearch.rawValue
        memoryWriteMode = record.memoryWriteMode.rawValue
        memoryEmbeddingsEnabled = record.memoryEmbeddingsEnabled
        uiModPath = record.uiModPath
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    var record: ProjectRecord {
        ProjectRecord(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            path: path,
            isGeneralProject: isGeneralProject,
            trustState: ProjectTrustState(rawValue: trustState) ?? .untrusted,
            sandboxMode: ProjectSandboxMode(rawValue: sandboxMode) ?? .readOnly,
            approvalPolicy: ProjectApprovalPolicy(rawValue: approvalPolicy) ?? .untrusted,
            networkAccess: networkAccess,
            webSearch: ProjectWebSearchMode(rawValue: webSearch) ?? .cached,
            memoryWriteMode: ProjectMemoryWriteMode(rawValue: memoryWriteMode) ?? .off,
            memoryEmbeddingsEnabled: memoryEmbeddingsEnabled,
            uiModPath: uiModPath?.isEmpty == false ? uiModPath : nil,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public final class SQLiteProjectRepository: ProjectRepository, @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func listProjects() async throws -> [ProjectRecord] {
        try await dbQueue.read { db in
            try ProjectEntity
                .order(Column("updatedAt").desc)
                .fetchAll(db)
                .map(\.record)
        }
    }

    public func getProject(id: UUID) async throws -> ProjectRecord? {
        try await dbQueue.read { db in
            try ProjectEntity.fetchOne(db, key: ["id": id.uuidString])?.record
        }
    }

    public func getProject(path: String) async throws -> ProjectRecord? {
        try await dbQueue.read { db in
            try ProjectEntity
                .filter(Column("path") == path)
                .fetchOne(db)?
                .record
        }
    }

    public func createProject(named name: String, path: String, trustState: ProjectTrustState, isGeneralProject: Bool = false) async throws -> ProjectRecord {
        try await dbQueue.write { db in
            let now = Date()
            let safety = ProjectSafetySettings.recommendedDefaults(for: trustState)
            let entity = ProjectEntity(
                record: ProjectRecord(
                    name: name,
                    path: path,
                    isGeneralProject: isGeneralProject,
                    trustState: trustState,
                    sandboxMode: safety.sandboxMode,
                    approvalPolicy: safety.approvalPolicy,
                    networkAccess: safety.networkAccess,
                    webSearch: safety.webSearch,
                    createdAt: now,
                    updatedAt: now
                )
            )
            try entity.insert(db)
            return entity.record
        }
    }

    public func deleteProject(id: UUID) async throws {
        try await dbQueue.write { db in
            let projectID = id.uuidString
            let projectKey = projectID.lowercased()

            try db.execute(
                sql: "DELETE FROM chat_search_index WHERE projectID = ?",
                arguments: [projectID]
            )

            // These tables are scoped by project but are not enforced via foreign keys.
            try db.execute(
                sql: "DELETE FROM skill_enablements WHERE target = 'project' AND projectID = ?",
                arguments: [projectID]
            )
            try db.execute(
                sql: "DELETE FROM project_skill_enablements WHERE projectID = ?",
                arguments: [projectID]
            )
            try db.execute(
                sql: "DELETE FROM extension_installs WHERE scope = 'project' AND projectID = ?",
                arguments: [projectID]
            )
            try db.execute(
                sql: "DELETE FROM computer_action_permissions WHERE projectKey = ?",
                arguments: [projectKey]
            )

            // Project deletion cascades to threads, follow-ups, mappings, and other FK-backed tables.
            try db.execute(
                sql: "DELETE FROM projects WHERE id = ?",
                arguments: [projectID]
            )
        }
    }

    public func updateProjectName(id: UUID, name: String) async throws -> ProjectRecord {
        try await dbQueue.write { db in
            guard var entity = try ProjectEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }
            entity.name = name
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
    }

    public func updateProjectPath(id: UUID, path: String) async throws -> ProjectRecord {
        try await dbQueue.write { db in
            guard var entity = try ProjectEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }
            entity.path = path
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
    }

    public func updateProjectTrustState(id: UUID, trustState: ProjectTrustState) async throws -> ProjectRecord {
        try await dbQueue.write { db in
            guard var entity = try ProjectEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }
            entity.trustState = trustState.rawValue
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
    }

    public func updateProjectSafetySettings(id: UUID, settings: ProjectSafetySettings) async throws -> ProjectRecord {
        try await dbQueue.write { db in
            guard var entity = try ProjectEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }

            entity.sandboxMode = settings.sandboxMode.rawValue
            entity.approvalPolicy = settings.approvalPolicy.rawValue
            entity.networkAccess = settings.networkAccess
            entity.webSearch = settings.webSearch.rawValue
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
    }

    public func updateProjectMemorySettings(id: UUID, settings: ProjectMemorySettings) async throws -> ProjectRecord {
        try await dbQueue.write { db in
            guard var entity = try ProjectEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }

            entity.memoryWriteMode = settings.writeMode.rawValue
            entity.memoryEmbeddingsEnabled = settings.embeddingsEnabled
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
    }

    public func updateProjectUIModPath(id: UUID, uiModPath: String?) async throws -> ProjectRecord {
        try await dbQueue.write { db in
            guard var entity = try ProjectEntity.fetchOne(db, key: ["id": id.uuidString]) else {
                throw CodexChatCoreError.missingRecord(id.uuidString)
            }

            entity.uiModPath = uiModPath
            entity.updatedAt = Date()
            try entity.update(db)
            return entity.record
        }
    }
}
