import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import CodexKit
import XCTest

@MainActor
final class SidebarSelectionTests: XCTestCase {
    func testProjectRowIsNotVisuallySelectedWhenThreadInProjectIsSelected() {
        let model = makeModel()
        let projectID = UUID()
        let threadID = UUID()

        model.selectedProjectID = projectID
        model.selectedThreadID = threadID
        model.threadsState = .loaded([
            ThreadRecord(id: threadID, projectId: projectID, title: "Chat"),
        ])

        XCTAssertFalse(model.isProjectSidebarVisuallySelected(projectID))
    }

    func testProjectRowIsVisuallySelectedWhenNoThreadIsSelected() {
        let model = makeModel()
        let projectID = UUID()

        model.selectedProjectID = projectID
        model.selectedThreadID = nil

        XCTAssertTrue(model.isProjectSidebarVisuallySelected(projectID))
    }

    func testToggleProjectExpandedTracksExpandedState() {
        let model = makeModel()
        let projectID = UUID()

        model.toggleProjectExpanded(projectID)
        XCTAssertTrue(model.expandedProjectIDs.contains(projectID))

        model.toggleProjectExpanded(projectID)
        XCTAssertFalse(model.expandedProjectIDs.contains(projectID))
    }

    func testPendingApprovalThreadIsTrackedForSidebarLabel() {
        let model = makeModel()
        let waitingThreadID = UUID()
        let otherThreadID = UUID()

        model.approvalStateMachine.enqueue(makeApprovalRequest(id: 901), threadID: waitingThreadID)
        model.syncApprovalPresentationState()

        XCTAssertTrue(model.pendingApprovalThreadIDs.contains(waitingThreadID))
        XCTAssertTrue(model.hasPendingApproval(for: waitingThreadID))
        XCTAssertFalse(model.hasPendingApproval(for: otherThreadID))
    }

    func testPendingApprovalForSelectedThreadBecomesActiveRequest() {
        let model = makeModel()
        let threadID = UUID()
        let request = makeApprovalRequest(id: 902)
        model.selectedThreadID = threadID

        model.approvalStateMachine.enqueue(request, threadID: threadID)
        model.syncApprovalPresentationState()

        XCTAssertEqual(model.activeApprovalRequest?.id, request.id)
        XCTAssertTrue(model.hasPendingApprovalForSelectedThread)
    }

    func testTrailingControlsVisibleWhenRowIsSelectedEvenWithoutHover() {
        XCTAssertTrue(
            SidebarView.trailingControlsVisible(isHovered: false, isSelected: true)
        )
        XCTAssertTrue(
            SidebarView.trailingControlsVisible(isHovered: true, isSelected: false)
        )
        XCTAssertFalse(
            SidebarView.trailingControlsVisible(isHovered: false, isSelected: false)
        )
    }

    func testThreadTrailingControlsAppearOnHoverOrSelection() {
        XCTAssertFalse(
            SidebarView.threadTrailingControlsVisible(
                isHovered: true,
                isSelected: true,
                isSelectionSuppressed: true
            )
        )
        XCTAssertTrue(
            SidebarView.threadTrailingControlsVisible(
                isHovered: false,
                isSelected: true,
                isSelectionSuppressed: false
            )
        )
        XCTAssertTrue(
            SidebarView.threadTrailingControlsVisible(
                isHovered: true,
                isSelected: true,
                isSelectionSuppressed: false
            )
        )
    }

    func testFilteredThreadsSupportsPendingAndUnreadModes() {
        let pendingThread = ThreadRecord(id: UUID(), projectId: UUID(), title: "Pending")
        let unreadThread = ThreadRecord(id: UUID(), projectId: UUID(), title: "Unread")
        let plainThread = ThreadRecord(id: UUID(), projectId: UUID(), title: "Plain")
        let all = [pendingThread, unreadThread, plainThread]

        let pendingOnly = SidebarView.filteredThreads(
            all,
            filter: .pending,
            pendingThreadIDs: [pendingThread.id],
            unreadThreadIDs: [unreadThread.id]
        )
        XCTAssertEqual(pendingOnly.map(\.id), [pendingThread.id])

        let unreadOnly = SidebarView.filteredThreads(
            all,
            filter: .unread,
            pendingThreadIDs: [pendingThread.id],
            unreadThreadIDs: [unreadThread.id]
        )
        XCTAssertEqual(unreadOnly.map(\.id), [unreadThread.id])

        let allThreads = SidebarView.filteredThreads(
            all,
            filter: .all,
            pendingThreadIDs: [pendingThread.id],
            unreadThreadIDs: [unreadThread.id]
        )
        XCTAssertEqual(allThreads.map(\.id), all.map(\.id))
    }

    func testRecentThreadsSortByUpdatedAtDescendingAndApplyLimit() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let oldestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let middleID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let newestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let oldest = ThreadRecord(
            id: oldestID,
            projectId: UUID(),
            title: "Oldest",
            updatedAt: base.addingTimeInterval(-120)
        )
        let middle = ThreadRecord(
            id: middleID,
            projectId: UUID(),
            title: "Middle",
            updatedAt: base.addingTimeInterval(-60)
        )
        let newest = ThreadRecord(
            id: newestID,
            projectId: UUID(),
            title: "Newest",
            updatedAt: base
        )

        let recents = SidebarView.recentThreads(
            [middle, oldest, newest],
            filter: .all,
            pendingThreadIDs: [],
            unreadThreadIDs: [],
            limit: 2
        )

        XCTAssertEqual(recents.map(\.id), [newest.id, middle.id])
    }

    func testRecentThreadsApplyFilterBeforeSorting() {
        let base = Date(timeIntervalSince1970: 1_700_000_100)
        let pending = ThreadRecord(id: UUID(), projectId: UUID(), title: "Pending", updatedAt: base)
        let unread = ThreadRecord(
            id: UUID(),
            projectId: UUID(),
            title: "Unread",
            updatedAt: base.addingTimeInterval(-10)
        )

        let recents = SidebarView.recentThreads(
            [unread, pending],
            filter: .pending,
            pendingThreadIDs: [pending.id],
            unreadThreadIDs: [unread.id]
        )

        XCTAssertEqual(recents.map(\.id), [pending.id])
    }

    func testRecentThreadsDeduplicatesSameThreadIDAcrossSources() throws {
        let id = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let older = ThreadRecord(
            id: id,
            projectId: UUID(),
            title: "Simple greeting",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = ThreadRecord(
            id: id,
            projectId: UUID(),
            title: "Simple greeting",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_050)
        )

        let recents = SidebarView.recentThreads(
            [older, newer],
            filter: .all,
            pendingThreadIDs: [],
            unreadThreadIDs: []
        )

        XCTAssertEqual(recents.count, 1)
        XCTAssertEqual(recents.first?.id, id)
        XCTAssertEqual(recents.first?.updatedAt, newer.updatedAt)
    }

    func testIsDarkColorHexDetectsDarkAndLightColors() {
        XCTAssertTrue(SidebarView.isDarkColorHex("#0A0A0A"))
        XCTAssertFalse(SidebarView.isDarkColorHex("#F5F5F5"))
    }

    func testIsDarkColorHexSupportsShorthandHex() {
        XCTAssertTrue(SidebarView.isDarkColorHex("#111"))
        XCTAssertFalse(SidebarView.isDarkColorHex("#EEE"))
    }

    func testRemoveSelectedProjectDisconnectsItAndKeepsFilesOnDisk() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-remove-project-\(UUID().uuidString)", isDirectory: true)
        let firstProjectURL = root.appendingPathComponent("first", isDirectory: true)
        let secondProjectURL = root.appendingPathComponent("second", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: firstProjectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondProjectURL, withIntermediateDirectories: true)

        let database = try MetadataDatabase(databaseURL: root.appendingPathComponent("metadata.sqlite"))
        let repositories = MetadataRepositories(database: database)

        let firstProject = try await repositories.projectRepository.createProject(
            named: "First",
            path: firstProjectURL.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let secondProject = try await repositories.projectRepository.createProject(
            named: "Second",
            path: secondProjectURL.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        _ = try await repositories.threadRepository.createThread(projectID: secondProject.id, title: "Second thread")

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        try await model.refreshProjects()
        model.selectedProjectID = firstProject.id

        model.removeSelectedProjectFromCodexChat()

        try await waitUntil {
            !model.projects.contains(where: { $0.id == firstProject.id })
                && model.selectedProjectID == secondProject.id
        }

        let removedProject = try await repositories.projectRepository.getProject(id: firstProject.id)
        XCTAssertNil(removedProject)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstProjectURL.path))
        XCTAssertEqual(model.selectedProjectID, secondProject.id)
    }

    private func makeModel() -> AppModel {
        let model = AppModel(
            repositories: nil,
            runtime: CodexRuntime(executableResolver: { nil }),
            bootError: nil
        )
        model.runtimeStatus = .connected
        model.accountState = RuntimeAccountState(account: nil, authMode: .unknown, requiresOpenAIAuth: false)
        return model
    }

    private func makeApprovalRequest(id: Int) -> RuntimeApprovalRequest {
        RuntimeApprovalRequest(
            id: id,
            kind: .commandExecution,
            method: "item/commandExecution/requestApproval",
            threadID: "thr_\(id)",
            turnID: "turn_\(id)",
            itemID: "item_\(id)",
            reason: "approval",
            risk: nil,
            cwd: "/tmp",
            command: ["echo", "test"],
            changes: [],
            detail: "{}"
        )
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
