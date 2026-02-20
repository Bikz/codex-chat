import CodexChatInfra
@testable import CodexChatShared
import XCTest

final class AppModelProjectCreationBehaviorTests: XCTestCase {
    @MainActor
    func testCreateManagedProjectAutoTrustsAndOpensDraftInProject() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-project-create-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storagePaths = CodexChatStoragePaths(rootURL: root)
        try storagePaths.ensureRootStructure()

        let database = try MetadataDatabase(databaseURL: storagePaths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths
        )

        try await model.refreshProjects()
        try await model.ensureGeneralProject()
        try await model.refreshProjects()

        let created = await model.createManagedProject(named: "Acme Platform")
        XCTAssertTrue(created)

        let selectedProject = try XCTUnwrap(model.selectedProject)
        let expectedPath = storagePaths.projectsURL
            .appendingPathComponent("Acme Platform", isDirectory: true)
            .path

        XCTAssertEqual(selectedProject.name, "Acme Platform")
        XCTAssertEqual(selectedProject.path, expectedPath)
        XCTAssertEqual(selectedProject.trustState, .trusted)
        XCTAssertFalse(selectedProject.isGeneralProject)

        XCTAssertNil(model.selectedThreadID)
        XCTAssertEqual(model.draftChatProjectID, selectedProject.id)
        XCTAssertEqual(model.detailDestination, .thread)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: storagePaths.projectsURL.appendingPathComponent("Acme-Platform", isDirectory: true).path
            )
        )

        let persistedProject = try await repositories.projectRepository.getProject(id: selectedProject.id)
        XCTAssertEqual(persistedProject?.trustState, .trusted)
        XCTAssertEqual(persistedProject?.name, "Acme Platform")
        XCTAssertEqual(persistedProject?.path, expectedPath)

        let threads = try await repositories.threadRepository.listThreads(projectID: selectedProject.id)
        XCTAssertTrue(threads.isEmpty)
    }

    @MainActor
    func testUniqueUserNamedProjectDirectoryURLPreservesSpacesAndUsesNumericSuffix() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-project-name-preserve-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storagePaths = CodexChatStoragePaths(rootURL: root)
        try storagePaths.ensureRootStructure()

        let first = storagePaths.uniqueUserNamedProjectDirectoryURL(requestedName: "My App")
        XCTAssertEqual(first.lastPathComponent, "My App")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)

        let second = storagePaths.uniqueUserNamedProjectDirectoryURL(requestedName: "My App")
        XCTAssertEqual(second.lastPathComponent, "My App 2")
    }
}
