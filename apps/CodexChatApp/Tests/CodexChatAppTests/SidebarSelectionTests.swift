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
