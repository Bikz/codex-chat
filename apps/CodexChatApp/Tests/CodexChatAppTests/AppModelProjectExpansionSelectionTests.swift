import CodexChatInfra
@testable import CodexChatShared
import XCTest

@MainActor
final class AppModelProjectExpansionSelectionTests: XCTestCase {
    func testToggleProjectExpandedDoesNotChangeSelectedProjectOrThread() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let selectedProjectID = UUID()
        let selectedThreadID = UUID()
        let otherProjectID = UUID()

        model.selectedProjectID = selectedProjectID
        model.selectedThreadID = selectedThreadID

        model.toggleProjectExpanded(otherProjectID)

        XCTAssertEqual(model.selectedProjectID, selectedProjectID)
        XCTAssertEqual(model.selectedThreadID, selectedThreadID)
        XCTAssertTrue(model.expandedProjectIDs.contains(otherProjectID))

        model.toggleProjectExpanded(otherProjectID)

        XCTAssertEqual(model.selectedProjectID, selectedProjectID)
        XCTAssertEqual(model.selectedThreadID, selectedThreadID)
        XCTAssertFalse(model.expandedProjectIDs.contains(otherProjectID))
    }

    func testListThreadsForProjectDoesNotChangeCurrentSelection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-project-expansion-selection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let database = try MetadataDatabase(databaseURL: root.appendingPathComponent("metadata.sqlite"))
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        let selectedProject = try await repositories.projectRepository.createProject(
            named: "Selected",
            path: root.appendingPathComponent("selected", isDirectory: true).path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let expandedProject = try await repositories.projectRepository.createProject(
            named: "Expanded",
            path: root.appendingPathComponent("expanded", isDirectory: true).path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let selectedThread = try await repositories.threadRepository.createThread(
            projectID: selectedProject.id,
            title: "Selected thread"
        )
        _ = try await repositories.threadRepository.createThread(
            projectID: expandedProject.id,
            title: "Expanded thread 1"
        )
        _ = try await repositories.threadRepository.createThread(
            projectID: expandedProject.id,
            title: "Expanded thread 2"
        )

        model.selectedProjectID = selectedProject.id
        model.selectedThreadID = selectedThread.id

        let loadedThreads = try await model.listThreadsForProject(expandedProject.id)

        XCTAssertEqual(loadedThreads.count, 2)
        XCTAssertEqual(model.selectedProjectID, selectedProject.id)
        XCTAssertEqual(model.selectedThreadID, selectedThread.id)
    }

    func testActivateProjectFromSidebarStartsDraftAndTogglesExpandedState() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let projectID = UUID()
        let previouslySelectedThreadID = UUID()

        model.selectedProjectID = UUID()
        model.selectedThreadID = previouslySelectedThreadID

        let expandedAfterFirstTap = model.activateProjectFromSidebar(projectID)

        XCTAssertTrue(expandedAfterFirstTap)
        XCTAssertTrue(model.expandedProjectIDs.contains(projectID))
        XCTAssertEqual(model.selectedProjectID, projectID)
        XCTAssertNil(model.selectedThreadID)
        XCTAssertEqual(model.draftChatProjectID, projectID)
        XCTAssertEqual(model.detailDestination, .thread)

        let expandedAfterSecondTap = model.activateProjectFromSidebar(projectID)

        XCTAssertFalse(expandedAfterSecondTap)
        XCTAssertFalse(model.expandedProjectIDs.contains(projectID))
        XCTAssertEqual(model.selectedProjectID, projectID)
        XCTAssertNil(model.selectedThreadID)
        XCTAssertEqual(model.draftChatProjectID, projectID)
        XCTAssertEqual(model.detailDestination, .thread)
    }
}
