import CodexChatCore
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
}
