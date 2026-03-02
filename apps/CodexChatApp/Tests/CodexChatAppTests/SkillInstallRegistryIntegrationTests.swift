import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import CodexSkills
import Foundation
import XCTest

@MainActor
final class SkillInstallRegistryIntegrationTests: XCTestCase {
    func testProjectScopedInstallRegistersSkillAndCreatesProjectSymlink() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-skill-install-integration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure()
        let projectPath = root.appendingPathComponent("project-alpha", isDirectory: true)
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)

        let database = try MetadataDatabase(databaseURL: paths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let project = try await repositories.projectRepository.createProject(
            named: "Alpha",
            path: projectPath.path,
            trustState: .trusted,
            isGeneralProject: false
        )

        let catalogService = SkillCatalogService(
            codexHomeURL: paths.codexHomeURL,
            agentsHomeURL: paths.agentsHomeURL,
            sharedSkillsStoreURL: paths.sharedSkillsStoreURL,
            processRunner: { argv, _ in
                if argv.prefix(4) == ["git", "clone", "--depth", "1"], let destination = argv.last {
                    let destinationURL = URL(fileURLWithPath: destination, isDirectory: true)
                    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                    try """
                    # Agent Browser

                    Web automation helper.
                    """.write(
                        to: destinationURL.appendingPathComponent("SKILL.md", isDirectory: false),
                        atomically: true,
                        encoding: .utf8
                    )
                }
                return "ok"
            }
        )

        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            skillCatalogService: catalogService,
            storagePaths: paths
        )
        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id

        model.installSkill(
            source: "https://github.com/openai/agent-browser.git",
            scope: .project,
            installer: .git
        )

        try await waitUntil(timeout: 3) {
            !model.isSkillOperationInProgress && model.skillStatusMessage?.hasPrefix("Installed skill to ") == true
        }

        let installs = try await repositories.skillInstallRegistryRepository.list()
        XCTAssertEqual(installs.count, 1)
        let install = try XCTUnwrap(installs.first)
        XCTAssertEqual(install.mode, .selected)
        XCTAssertEqual(install.projectIDs, [project.id])

        let sharedSkillFolder = URL(fileURLWithPath: install.sharedPath, isDirectory: true).lastPathComponent
        let projectLinkPath = projectPath
            .appendingPathComponent(".agents/skills", isDirectory: true)
            .appendingPathComponent(sharedSkillFolder, isDirectory: true)
            .path

        XCTAssertTrue(FileManager.default.fileExists(atPath: projectLinkPath))
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: projectLinkPath)
        XCTAssertEqual(destination, install.sharedPath)
    }

    func testRefreshSkillsMigratesLegacyEnablementIntoSharedStoreRegistry() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-skill-legacy-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure()

        let projectPath = root.appendingPathComponent("project-beta", isDirectory: true)
        let legacySkillPath = projectPath
            .appendingPathComponent(".agents/skills/legacy-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: legacySkillPath, withIntermediateDirectories: true)
        try """
        # Legacy Skill

        Migrated legacy skill.
        """.write(
            to: legacySkillPath.appendingPathComponent("SKILL.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let database = try MetadataDatabase(databaseURL: paths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let project = try await repositories.projectRepository.createProject(
            named: "Beta",
            path: projectPath.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        try await repositories.projectSkillEnablementRepository.setSkillEnabled(
            projectID: project.id,
            skillPath: legacySkillPath.path,
            enabled: true
        )

        let catalogService = SkillCatalogService(
            codexHomeURL: paths.codexHomeURL,
            agentsHomeURL: paths.agentsHomeURL,
            sharedSkillsStoreURL: paths.sharedSkillsStoreURL
        )
        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            skillCatalogService: catalogService,
            storagePaths: paths
        )
        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id

        try await model.refreshSkills()

        let installs = try await repositories.skillInstallRegistryRepository.list()
        XCTAssertEqual(installs.count, 1)
        let install = try XCTUnwrap(installs.first)
        XCTAssertEqual(install.mode, .selected)
        XCTAssertEqual(install.projectIDs, [project.id])
        XCTAssertTrue(CodexChatStoragePaths.isPath(install.sharedPath, insideRoot: paths.sharedSkillsStoreURL.path))

        let projectLinkPath = projectPath
            .appendingPathComponent(".agents/skills", isDirectory: true)
            .appendingPathComponent(URL(fileURLWithPath: install.sharedPath, isDirectory: true).lastPathComponent, isDirectory: true)
            .path
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectLinkPath))
        let linkDestination = try FileManager.default.destinationOfSymbolicLink(atPath: projectLinkPath)
        XCTAssertEqual(linkDestination, install.sharedPath)

        let migrationMarker = try await repositories.preferenceRepository.getPreference(key: .skillsInstallMigrationV1)
        XCTAssertEqual(migrationMarker, "1")
    }

    func testUninstallRefusesToDeleteSharedStoreRootPath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-skill-uninstall-root-guard-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure()
        let projectPath = root.appendingPathComponent("project-gamma", isDirectory: true)
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)

        let database = try MetadataDatabase(databaseURL: paths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let project = try await repositories.projectRepository.createProject(
            named: "Gamma",
            path: projectPath.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        _ = try await repositories.skillInstallRegistryRepository.upsert(
            SkillInstallRecord(
                skillID: "dangerous-root-record",
                source: "local:dangerous-root",
                installer: .git,
                sharedPath: paths.sharedSkillsStoreURL.path,
                mode: .selected,
                projectIDs: [project.id]
            )
        )

        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            storagePaths: paths
        )
        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id

        let dangerousSkill = DiscoveredSkill(
            name: "Dangerous Root Skill",
            description: "Synthetic skill for uninstall safety test.",
            scope: .global,
            skillPath: paths.sharedSkillsStoreURL.path,
            skillDefinitionPath: paths.sharedSkillsStoreURL.appendingPathComponent("SKILL.md", isDirectory: false).path,
            hasScripts: false,
            sourceURL: nil,
            optionalMetadata: [:],
            installMetadata: nil,
            isGitRepository: false
        )
        let item = AppModel.SkillListItem(
            skill: dangerousSkill,
            enabledTargets: [.project],
            isEnabledForSelectedProject: true,
            selectedProjectCount: 1,
            updateCapability: .unavailable,
            updateSource: nil,
            updateInstaller: nil
        )

        model.uninstallSkill(item)

        try await waitUntil(timeout: 3) {
            !model.isSkillOperationInProgress && (model.skillStatusMessage?.contains("Refusing to remove a shared skill path outside the managed store.") ?? false)
        }

        let installs = try await repositories.skillInstallRegistryRepository.list()
        XCTAssertEqual(installs.count, 1)
        XCTAssertEqual(installs.first?.skillID, "dangerous-root-record")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.sharedSkillsStoreURL.path))
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Timed out waiting for condition.")
    }
}
