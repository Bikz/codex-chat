import CodexChatCore
@testable import CodexChatInfra
import Foundation
import GRDB
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
        XCTAssertTrue(tableNames.contains("skill_enablements"))
        XCTAssertTrue(tableNames.contains("chat_search_index"))
        XCTAssertTrue(tableNames.contains("follow_up_queue"))
        XCTAssertTrue(tableNames.contains("extension_installs"))
        XCTAssertTrue(tableNames.contains("extension_permissions"))
        XCTAssertTrue(tableNames.contains("extension_hook_state"))
        XCTAssertTrue(tableNames.contains("extension_automation_state"))

        let threadColumns = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('threads')")
        }
        XCTAssertTrue(threadColumns.contains("isPinned"))
        XCTAssertTrue(threadColumns.contains("archivedAt"))

        let extensionInstallColumns = try database.dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('extension_installs')")
        }
        XCTAssertTrue(extensionInstallColumns.contains("projectID"))
    }

    func testProjectThreadAndPreferencePersistence() async throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let repositories = MetadataRepositories(database: database)

        let project = try await repositories.projectRepository.createProject(
            named: "Inbox",
            path: "/tmp/inbox",
            trustState: .untrusted,
            isGeneralProject: false
        )
        XCTAssertEqual(project.name, "Inbox")
        XCTAssertEqual(project.path, "/tmp/inbox")
        XCTAssertEqual(project.sandboxMode, .readOnly)
        XCTAssertEqual(project.approvalPolicy, .untrusted)
        XCTAssertEqual(project.networkAccess, false)
        XCTAssertEqual(project.webSearch, .cached)
        XCTAssertEqual(project.memoryWriteMode, .off)
        XCTAssertEqual(project.memoryEmbeddingsEnabled, false)
        XCTAssertNil(project.uiModPath)

        let thread = try await repositories.threadRepository.createThread(projectID: project.id, title: "First")
        XCTAssertEqual(thread.projectId, project.id)
        XCTAssertFalse(thread.isPinned)
        XCTAssertNil(thread.archivedAt)

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

        let updatedMemory = try await repositories.projectRepository.updateProjectMemorySettings(
            id: project.id,
            settings: ProjectMemorySettings(writeMode: .summariesOnly, embeddingsEnabled: true)
        )
        XCTAssertEqual(updatedMemory.memoryWriteMode, .summariesOnly)
        XCTAssertEqual(updatedMemory.memoryEmbeddingsEnabled, true)

        let updatedMod = try await repositories.projectRepository.updateProjectUIModPath(
            id: project.id,
            uiModPath: "/tmp/inbox/mods/glass-green"
        )
        XCTAssertEqual(updatedMod.uiModPath, "/tmp/inbox/mods/glass-green")

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

        try await repositories.projectSkillEnablementRepository.setSkillEnabled(
            target: .global,
            projectID: nil,
            skillPath: "/tmp/inbox/.agents/skills/my-skill",
            enabled: true
        )
        let resolved = try await repositories.projectSkillEnablementRepository.resolvedEnabledSkillPaths(
            forProjectID: project.id,
            generalProjectID: nil
        )
        XCTAssertTrue(resolved.contains("/tmp/inbox/.agents/skills/my-skill"))

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

        _ = try await repositories.threadRepository.archiveThread(id: thread.id, archivedAt: Date())
        let archivedSearchResults = try await repositories.chatSearchRepository.search(
            query: "archive persistence",
            projectID: project.id,
            limit: 10
        )
        XCTAssertTrue(archivedSearchResults.isEmpty)

        let extensionInstall = ExtensionInstallRecord(
            id: "global:com.example.mod",
            modID: "com.example.mod",
            scope: .global,
            sourceURL: "https://github.com/example/mod",
            installedPath: "/tmp/mod",
            enabled: true
        )
        let storedInstall = try await repositories.extensionInstallRepository.upsert(extensionInstall)
        XCTAssertEqual(storedInstall.modID, extensionInstall.modID)

        try await repositories.extensionPermissionRepository.set(
            modID: extensionInstall.modID,
            permissionKey: .projectRead,
            status: .granted,
            grantedAt: Date()
        )
        let permissions = try await repositories.extensionPermissionRepository.list(modID: extensionInstall.modID)
        XCTAssertEqual(permissions.count, 1)
        XCTAssertEqual(permissions.first?.status, .granted)

        let hookState = try await repositories.extensionHookStateRepository.upsert(
            ExtensionHookStateRecord(modID: extensionInstall.modID, hookID: "turn-summary", lastStatus: "ok")
        )
        XCTAssertEqual(hookState.hookID, "turn-summary")

        let automationState = try await repositories.extensionAutomationStateRepository.upsert(
            ExtensionAutomationStateRecord(
                modID: extensionInstall.modID,
                automationID: "daily-notes",
                nextRunAt: Date().addingTimeInterval(3600),
                lastStatus: "scheduled",
                launchdLabel: "app.codexchat.daily-notes"
            )
        )
        XCTAssertEqual(automationState.automationID, "daily-notes")
    }

    func testThreadPinAndArchiveOrdering() async throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let repositories = MetadataRepositories(database: database)

        let project = try await repositories.projectRepository.createProject(
            named: "Threads",
            path: "/tmp/threads",
            trustState: .trusted,
            isGeneralProject: false
        )

        let first = try await repositories.threadRepository.createThread(projectID: project.id, title: "First")
        let second = try await repositories.threadRepository.createThread(projectID: project.id, title: "Second")
        _ = try await repositories.threadRepository.touchThread(id: first.id)

        _ = try await repositories.threadRepository.setThreadPinned(id: second.id, isPinned: true)
        let active = try await repositories.threadRepository.listThreads(projectID: project.id)
        XCTAssertEqual(active.first?.id, second.id)
        XCTAssertEqual(active.count, 2)

        _ = try await repositories.threadRepository.archiveThread(id: second.id, archivedAt: Date())
        let activeAfterArchive = try await repositories.threadRepository.listThreads(projectID: project.id)
        XCTAssertEqual(activeAfterArchive.map(\.id), [first.id])

        let archived = try await repositories.threadRepository.listArchivedThreads()
        XCTAssertEqual(archived.first?.id, second.id)
        XCTAssertEqual(archived.first?.isPinned, false)

        let unarchived = try await repositories.threadRepository.unarchiveThread(id: second.id)
        XCTAssertNil(unarchived.archivedAt)
        XCTAssertFalse(unarchived.isPinned)
    }

    func testFollowUpQueuePersistenceAndOrdering() async throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let repositories = MetadataRepositories(database: database)

        let project = try await repositories.projectRepository.createProject(
            named: "Queue Project",
            path: "/tmp/queue-project",
            trustState: .trusted,
            isGeneralProject: false
        )
        let thread = try await repositories.threadRepository.createThread(
            projectID: project.id,
            title: "Queue Thread"
        )

        let first = FollowUpQueueItemRecord(
            threadID: thread.id,
            source: .userQueued,
            dispatchMode: .auto,
            text: "first",
            sortIndex: 0
        )
        let second = FollowUpQueueItemRecord(
            threadID: thread.id,
            source: .assistantSuggestion,
            dispatchMode: .auto,
            text: "second",
            sortIndex: 1,
            originSuggestionID: "s-1"
        )

        try await repositories.followUpQueueRepository.enqueue(first)
        try await repositories.followUpQueueRepository.enqueue(second)

        var loaded = try await repositories.followUpQueueRepository.list(threadID: thread.id)
        XCTAssertEqual(loaded.map(\.text), ["first", "second"])

        let updated = try await repositories.followUpQueueRepository.updateText(id: second.id, text: "second-updated")
        XCTAssertEqual(updated.text, "second-updated")

        try await repositories.followUpQueueRepository.move(id: second.id, threadID: thread.id, toSortIndex: 0)

        loaded = try await repositories.followUpQueueRepository.list(threadID: thread.id)
        XCTAssertEqual(loaded.map(\.text), ["second-updated", "first"])
        XCTAssertEqual(loaded.map(\.sortIndex), [0, 1])

        let preferred = try await repositories.followUpQueueRepository.listNextAutoCandidate(preferredThreadID: thread.id)
        XCTAssertEqual(preferred?.id, second.id)

        try await repositories.followUpQueueRepository.markFailed(id: second.id, error: "boom")
        let afterFailure = try await repositories.followUpQueueRepository.list(threadID: thread.id)
        let failed = try XCTUnwrap(afterFailure.first(where: { $0.id == second.id }))
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.lastError, "boom")

        try await repositories.followUpQueueRepository.markPending(id: second.id)
        let pending = try await repositories.followUpQueueRepository.list(threadID: thread.id)
        XCTAssertEqual(pending.first(where: { $0.id == second.id })?.state, .pending)

        try await repositories.followUpQueueRepository.delete(id: second.id)
        let afterDelete = try await repositories.followUpQueueRepository.list(threadID: thread.id)
        XCTAssertEqual(afterDelete.map(\.text), ["first"])
        XCTAssertEqual(afterDelete.first?.sortIndex, 0)
    }

    func testExtensionInstallRecordsAreScopedByProjectID() async throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let repositories = MetadataRepositories(database: database)

        let firstProject = try await repositories.projectRepository.createProject(
            named: "First",
            path: "/tmp/ext-first",
            trustState: .trusted,
            isGeneralProject: false
        )
        let secondProject = try await repositories.projectRepository.createProject(
            named: "Second",
            path: "/tmp/ext-second",
            trustState: .trusted,
            isGeneralProject: false
        )

        let firstRecord = ExtensionInstallRecord(
            id: "project:\(firstProject.id.uuidString.lowercased()):com.example.same-mod",
            modID: "com.example.same-mod",
            scope: .project,
            projectID: firstProject.id,
            sourceURL: "https://github.com/example/same-mod",
            installedPath: "/tmp/ext-first/mods/same-mod",
            enabled: true
        )
        let secondRecord = ExtensionInstallRecord(
            id: "project:\(secondProject.id.uuidString.lowercased()):com.example.same-mod",
            modID: "com.example.same-mod",
            scope: .project,
            projectID: secondProject.id,
            sourceURL: "https://github.com/example/same-mod",
            installedPath: "/tmp/ext-second/mods/same-mod",
            enabled: true
        )

        _ = try await repositories.extensionInstallRepository.upsert(firstRecord)
        _ = try await repositories.extensionInstallRepository.upsert(secondRecord)

        let installs = try await repositories.extensionInstallRepository.list()
        XCTAssertEqual(installs.count(where: { $0.modID == "com.example.same-mod" }), 2)
        XCTAssertTrue(installs.contains { $0.projectID == firstProject.id })
        XCTAssertTrue(installs.contains { $0.projectID == secondProject.id })
    }

    func testDeleteProjectRemovesProjectScopedDataAndCascadesThreads() async throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let repositories = MetadataRepositories(database: database)

        let firstProject = try await repositories.projectRepository.createProject(
            named: "First",
            path: "/tmp/delete-first",
            trustState: .trusted,
            isGeneralProject: false
        )
        let secondProject = try await repositories.projectRepository.createProject(
            named: "Second",
            path: "/tmp/delete-second",
            trustState: .trusted,
            isGeneralProject: false
        )

        let firstThread = try await repositories.threadRepository.createThread(
            projectID: firstProject.id,
            title: "First thread"
        )
        let secondThread = try await repositories.threadRepository.createThread(
            projectID: secondProject.id,
            title: "Second thread"
        )

        try await repositories.chatSearchRepository.indexThreadTitle(
            threadID: firstThread.id,
            projectID: firstProject.id,
            title: "Cleanup candidate"
        )
        try await repositories.chatSearchRepository.indexMessageExcerpt(
            threadID: firstThread.id,
            projectID: firstProject.id,
            text: "Delete this project metadata"
        )
        try await repositories.chatSearchRepository.indexThreadTitle(
            threadID: secondThread.id,
            projectID: secondProject.id,
            title: "Keep this project"
        )

        try await repositories.projectSkillEnablementRepository.setSkillEnabled(
            target: .project,
            projectID: firstProject.id,
            skillPath: "/tmp/delete-first/.agents/skills/demo",
            enabled: true
        )

        let firstInstall = ExtensionInstallRecord(
            id: "project:\(firstProject.id.uuidString.lowercased()):com.example.first",
            modID: "com.example.first",
            scope: .project,
            projectID: firstProject.id,
            sourceURL: "https://github.com/example/first",
            installedPath: "/tmp/delete-first/mods/first",
            enabled: true
        )
        let secondInstall = ExtensionInstallRecord(
            id: "project:\(secondProject.id.uuidString.lowercased()):com.example.second",
            modID: "com.example.second",
            scope: .project,
            projectID: secondProject.id,
            sourceURL: "https://github.com/example/second",
            installedPath: "/tmp/delete-second/mods/second",
            enabled: true
        )
        _ = try await repositories.extensionInstallRepository.upsert(firstInstall)
        _ = try await repositories.extensionInstallRepository.upsert(secondInstall)

        _ = try await repositories.computerActionPermissionRepository.set(
            actionID: "desktop.cleanup",
            projectID: firstProject.id,
            decision: .granted,
            decidedAt: Date()
        )
        _ = try await repositories.computerActionPermissionRepository.set(
            actionID: "desktop.cleanup",
            projectID: nil,
            decision: .granted,
            decidedAt: Date()
        )

        try await repositories.projectRepository.deleteProject(id: firstProject.id)

        let deletedProject = try await repositories.projectRepository.getProject(id: firstProject.id)
        XCTAssertNil(deletedProject)
        let retainedProject = try await repositories.projectRepository.getProject(id: secondProject.id)
        XCTAssertNotNil(retainedProject)

        let remainingThreads = try await repositories.threadRepository.listThreads(projectID: secondProject.id)
        XCTAssertEqual(remainingThreads.map(\.id), [secondThread.id])
        let deletedThread = try await repositories.threadRepository.getThread(id: firstThread.id)
        XCTAssertNil(deletedThread)

        let deletedProjectResults = try await repositories.chatSearchRepository.search(
            query: "delete this project metadata",
            projectID: firstProject.id,
            limit: 10
        )
        XCTAssertTrue(deletedProjectResults.isEmpty)

        let allResults = try await repositories.chatSearchRepository.search(
            query: "project",
            projectID: nil,
            limit: 20
        )
        XCTAssertFalse(allResults.contains { $0.threadID == firstThread.id })
        XCTAssertTrue(allResults.contains { $0.threadID == secondThread.id })

        let firstProjectEnabled = try await repositories.projectSkillEnablementRepository.enabledSkillPaths(
            target: .project,
            projectID: firstProject.id
        )
        XCTAssertTrue(firstProjectEnabled.isEmpty)

        let installs = try await repositories.extensionInstallRepository.list()
        XCTAssertFalse(installs.contains { $0.projectID == firstProject.id })
        XCTAssertTrue(installs.contains { $0.projectID == secondProject.id })

        let deletedProjectPermissions = try await repositories.computerActionPermissionRepository.list(projectID: firstProject.id)
        XCTAssertTrue(deletedProjectPermissions.isEmpty)

        let globalPermissions = try await repositories.computerActionPermissionRepository.list(projectID: nil)
        XCTAssertEqual(globalPermissions.map(\.actionID), ["desktop.cleanup"])
    }

    func testRewriteSkillPathsMigratesEnabledEntriesToNewRoot() async throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let repositories = MetadataRepositories(database: database)

        let project = try await repositories.projectRepository.createProject(
            named: "Skills",
            path: "/tmp/old-root/projects/skills",
            trustState: .trusted,
            isGeneralProject: false
        )

        try await repositories.projectSkillEnablementRepository.setSkillEnabled(
            projectID: project.id,
            skillPath: "/tmp/old-root/projects/skills/.agents/skills/a",
            enabled: true
        )
        try await repositories.projectSkillEnablementRepository.setSkillEnabled(
            projectID: project.id,
            skillPath: "/tmp/old-root/projects/skills/.agents/skills/b",
            enabled: false
        )

        try await repositories.projectSkillEnablementRepository.rewriteSkillPaths(
            projectID: project.id,
            fromRootPath: "/tmp/old-root",
            toRootPath: "/tmp/new-root"
        )

        let enabled = try await repositories.projectSkillEnablementRepository.enabledSkillPaths(projectID: project.id)
        XCTAssertTrue(enabled.contains("/tmp/new-root/projects/skills/.agents/skills/a"))
        XCTAssertFalse(enabled.contains("/tmp/old-root/projects/skills/.agents/skills/a"))

        let oldDisabledState = try await repositories.projectSkillEnablementRepository.isSkillEnabled(
            projectID: project.id,
            skillPath: "/tmp/old-root/projects/skills/.agents/skills/b"
        )
        XCTAssertFalse(oldDisabledState)

        let newDisabledState = try await repositories.projectSkillEnablementRepository.isSkillEnabled(
            projectID: project.id,
            skillPath: "/tmp/new-root/projects/skills/.agents/skills/b"
        )
        XCTAssertFalse(newDisabledState)
    }

    func testTargetScopedEnablementSupportsGlobalGeneralAndProject() async throws {
        let database = try MetadataDatabase(databaseURL: temporaryDatabaseURL())
        let repositories = MetadataRepositories(database: database)

        let project = try await repositories.projectRepository.createProject(
            named: "Scoped Skills",
            path: "/tmp/scoped/projects/skills",
            trustState: .trusted,
            isGeneralProject: false
        )

        try await repositories.projectSkillEnablementRepository.setSkillEnabled(
            target: .global,
            projectID: nil,
            skillPath: "/tmp/scoped/projects/skills/.agents/skills/a",
            enabled: true
        )
        try await repositories.projectSkillEnablementRepository.setSkillEnabled(
            target: .general,
            projectID: nil,
            skillPath: "/tmp/scoped/projects/skills/.agents/skills/b",
            enabled: true
        )
        try await repositories.projectSkillEnablementRepository.setSkillEnabled(
            target: .project,
            projectID: project.id,
            skillPath: "/tmp/scoped/projects/skills/.agents/skills/c",
            enabled: true
        )

        let global = try await repositories.projectSkillEnablementRepository.enabledSkillPaths(target: .global, projectID: nil)
        let general = try await repositories.projectSkillEnablementRepository.enabledSkillPaths(target: .general, projectID: nil)
        let projectScoped = try await repositories.projectSkillEnablementRepository.enabledSkillPaths(
            target: .project,
            projectID: project.id
        )
        XCTAssertTrue(global.contains("/tmp/scoped/projects/skills/.agents/skills/a"))
        XCTAssertTrue(general.contains("/tmp/scoped/projects/skills/.agents/skills/b"))
        XCTAssertTrue(projectScoped.contains("/tmp/scoped/projects/skills/.agents/skills/c"))

        let resolved = try await repositories.projectSkillEnablementRepository.resolvedEnabledSkillPaths(
            forProjectID: project.id,
            generalProjectID: nil
        )
        XCTAssertEqual(
            resolved,
            Set([
                "/tmp/scoped/projects/skills/.agents/skills/a",
                "/tmp/scoped/projects/skills/.agents/skills/b",
                "/tmp/scoped/projects/skills/.agents/skills/c",
            ])
        )
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-test-\(UUID().uuidString).sqlite")
    }
}
