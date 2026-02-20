@testable import CodexChatShared
import CodexKit
import XCTest

@MainActor
final class RuntimeApprovalFallbackTests: XCTestCase {
    func testUnscopedApprovalFallsBackToSingleActiveThread() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        let projectID = UUID()
        model.upsertActiveTurnContext(
            AppModel.ActiveTurnContext(
                localTurnID: UUID(),
                localThreadID: threadID,
                projectID: projectID,
                projectPath: "/tmp",
                runtimeThreadID: "w0|thr_single",
                runtimeTurnID: nil,
                memoryWriteMode: .off,
                userText: "hello",
                assistantText: "",
                actions: [],
                startedAt: Date()
            )
        )

        let request = RuntimeApprovalRequest(
            id: 11,
            kind: .commandExecution,
            method: "item/commandExecution/requestApproval",
            threadID: nil,
            turnID: nil,
            itemID: nil,
            reason: "needs approval",
            risk: nil,
            cwd: "/tmp",
            command: ["echo", "hello"],
            changes: [],
            detail: "{}"
        )

        model.handleRuntimeEvent(.approvalRequested(request))

        XCTAssertTrue(model.unscopedApprovalRequests.isEmpty)
        XCTAssertEqual(model.pendingApprovalThreadIDs, [threadID])
        XCTAssertEqual(model.approvalStateMachine.pendingRequest(for: threadID)?.id, request.id)
    }
}
