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

    func testActivateProjectFromSidebarStartsDraftAndTogglesExpandedState() async throws {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let projectID = UUID()
        let previouslySelectedThreadID = UUID()

        model.selectedProjectID = UUID()
        model.selectedThreadID = previouslySelectedThreadID

        let expandedAfterFirstTap = model.activateProjectFromSidebar(projectID)

        XCTAssertTrue(expandedAfterFirstTap)
        XCTAssertTrue(model.expandedProjectIDs.contains(projectID))
        try await waitUntil {
            model.selectedProjectID == projectID
                && model.selectedThreadID == nil
                && model.draftChatProjectID == projectID
                && model.detailDestination == .thread
        }

        let expandedAfterSecondTap = model.activateProjectFromSidebar(projectID)

        XCTAssertFalse(expandedAfterSecondTap)
        XCTAssertFalse(model.expandedProjectIDs.contains(projectID))
        try await waitUntil {
            model.selectedProjectID == projectID
                && model.selectedThreadID == nil
                && model.draftChatProjectID == projectID
                && model.detailDestination == .thread
        }
    }

    func testActivateProjectFromSidebarRestoresExistingThreadWhenAvailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-project-sidebar-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let database = try MetadataDatabase(databaseURL: root.appendingPathComponent("metadata.sqlite"))
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        let project = try await repositories.projectRepository.createProject(
            named: "Project",
            path: root.appendingPathComponent("project", isDirectory: true).path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let thread = try await repositories.threadRepository.createThread(
            projectID: project.id,
            title: "Existing thread"
        )
        try await model.refreshProjects()

        let isExpanded = model.activateProjectFromSidebar(project.id)
        XCTAssertTrue(isExpanded)
        XCTAssertTrue(model.expandedProjectIDs.contains(project.id))

        try await waitUntil(timeout: 8.0) {
            model.selectedProjectID == project.id
                && model.selectedThreadID == thread.id
        }

        XCTAssertNil(model.draftChatProjectID)
        XCTAssertEqual(model.detailDestination, .thread)
    }

    private func waitUntil(
        timeout: TimeInterval = 5.0,
        pollInterval: UInt64 = 50_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = Date()
        while true {
            if condition() {
                return
            }
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Condition not met within timeout")
                return
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
    }
}
