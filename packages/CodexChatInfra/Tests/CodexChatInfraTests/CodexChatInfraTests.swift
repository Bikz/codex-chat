import CodexChatCore
import Foundation
import GRDB
@testable import CodexChatInfra
import XCTest

final class CodexChatInfraTests: XCTestCase {
    func testMigrationCreatesExpectedTables() throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let tableNames = try database.dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }

        XCTAssertTrue(tableNames.contains("projects"))
        XCTAssertTrue(tableNames.contains("threads"))
        XCTAssertTrue(tableNames.contains("preferences"))
        XCTAssertTrue(tableNames.contains("runtime_thread_mappings"))
        XCTAssertTrue(tableNames.contains("project_secrets"))
        XCTAssertTrue(tableNames.contains("project_skill_enablements"))
        XCTAssertTrue(tableNames.contains("chat_search_index"))
    }

    func testProjectThreadAndPreferencePersistence() async throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let repositories = MetadataRepositories(database: database)

        let project = try await repositories.projectRepository.createProject(
            named: "Inbox",
            path: "/tmp/inbox",
            trustState: .untrusted
        )
        XCTAssertEqual(project.name, "Inbox")
        XCTAssertEqual(project.path, "/tmp/inbox")
        XCTAssertEqual(project.sandboxMode, .readOnly)
        XCTAssertEqual(project.approvalPolicy, .untrusted)
        XCTAssertEqual(project.networkAccess, false)
        XCTAssertEqual(project.webSearch, .cached)

        let thread = try await repositories.threadRepository.createThread(projectID: project.id, title: "First")
        XCTAssertEqual(thread.projectId, project.id)

        let listedProjects = try await repositories.projectRepository.listProjects()
        XCTAssertEqual(listedProjects.count, 1)
        XCTAssertEqual(listedProjects.first?.id, project.id)

        let listedThreads = try await repositories.threadRepository.listThreads(projectID: project.id)
        XCTAssertEqual(listedThreads.count, 1)
        XCTAssertEqual(listedThreads.first?.id, thread.id)

        try await repositories.preferenceRepository.setPreference(
            key: .lastOpenedProjectID,
            value: project.id.uuidString
        )

        let persistedProjectPreference = try await repositories.preferenceRepository.getPreference(key: .lastOpenedProjectID)
        XCTAssertEqual(persistedProjectPreference, project.id.uuidString)

        try await repositories.runtimeThreadMappingRepository.setRuntimeThreadID(
            localThreadID: thread.id,
            runtimeThreadID: "thr_123"
        )
        let runtimeThreadID = try await repositories.runtimeThreadMappingRepository.getRuntimeThreadID(localThreadID: thread.id)
        XCTAssertEqual(runtimeThreadID, "thr_123")
        let localThreadID = try await repositories.runtimeThreadMappingRepository.getLocalThreadID(runtimeThreadID: "thr_123")
        XCTAssertEqual(localThreadID, thread.id)

        let updatedProject = try await repositories.projectRepository.updateProjectSafetySettings(
            id: project.id,
            settings: ProjectSafetySettings(
                sandboxMode: .workspaceWrite,
                approvalPolicy: .onRequest,
                networkAccess: true,
                webSearch: .live
            )
        )
        XCTAssertEqual(updatedProject.sandboxMode, .workspaceWrite)
        XCTAssertEqual(updatedProject.approvalPolicy, .onRequest)
        XCTAssertEqual(updatedProject.networkAccess, true)
        XCTAssertEqual(updatedProject.webSearch, .live)

        let secret = try await repositories.projectSecretRepository.upsertSecret(
            projectID: project.id,
            name: "OPENAI_API_KEY",
            keychainAccount: "project-\(project.id.uuidString)-openai"
        )
        XCTAssertEqual(secret.projectID, project.id)

        let secrets = try await repositories.projectSecretRepository.listSecrets(projectID: project.id)
        XCTAssertEqual(secrets.count, 1)
        XCTAssertEqual(secrets.first?.name, "OPENAI_API_KEY")

        try await repositories.projectSecretRepository.deleteSecret(id: secret.id)
        let afterDelete = try await repositories.projectSecretRepository.listSecrets(projectID: project.id)
        XCTAssertTrue(afterDelete.isEmpty)

        try await repositories.projectSkillEnablementRepository.setSkillEnabled(
            projectID: project.id,
            skillPath: "/tmp/inbox/.agents/skills/my-skill",
            enabled: true
        )
        let isEnabled = try await repositories.projectSkillEnablementRepository.isSkillEnabled(
            projectID: project.id,
            skillPath: "/tmp/inbox/.agents/skills/my-skill"
        )
        XCTAssertTrue(isEnabled)
        let enabledPaths = try await repositories.projectSkillEnablementRepository.enabledSkillPaths(projectID: project.id)
        XCTAssertTrue(enabledPaths.contains("/tmp/inbox/.agents/skills/my-skill"))

        try await repositories.projectSkillEnablementRepository.setSkillEnabled(
            projectID: project.id,
            skillPath: "/tmp/inbox/.agents/skills/my-skill",
            enabled: false
        )
        let isEnabledAfterDisable = try await repositories.projectSkillEnablementRepository.isSkillEnabled(
            projectID: project.id,
            skillPath: "/tmp/inbox/.agents/skills/my-skill"
        )
        XCTAssertFalse(isEnabledAfterDisable)

        try await repositories.chatSearchRepository.indexThreadTitle(
            threadID: thread.id,
            projectID: project.id,
            title: "First thread"
        )
        try await repositories.chatSearchRepository.indexMessageExcerpt(
            threadID: thread.id,
            projectID: project.id,
            text: "Need to fix archive persistence"
        )

        let searchResults = try await repositories.chatSearchRepository.search(
            query: "archive persistence",
            projectID: project.id,
            limit: 10
        )
        XCTAssertFalse(searchResults.isEmpty)
        XCTAssertEqual(searchResults.first?.threadID, thread.id)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-test-\(UUID().uuidString).sqlite")
    }
}
