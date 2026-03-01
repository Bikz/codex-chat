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
