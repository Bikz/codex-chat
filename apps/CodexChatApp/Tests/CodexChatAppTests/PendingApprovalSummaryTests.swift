import CodexChatCore
@testable import CodexChatShared
import CodexKit
import XCTest

@MainActor
final class PendingApprovalSummaryTests: XCTestCase {
    func testPendingApprovalSummariesIncludeScopedAndUnscopedRequests() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        let request = makeApprovalRequest(id: 801)
        model.threadsState = .loaded([
            ThreadRecord(id: threadID, projectId: UUID(), title: "Needs review"),
        ])
        model.approvalStateMachine.enqueue(request, threadID: threadID)
        model.unscopedApprovalRequests = [makeApprovalRequest(id: 802)]
        model.syncApprovalPresentationState()

        let summaries = model.pendingApprovalSummaries
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries.first?.threadID, nil)
        XCTAssertEqual(summaries.first?.count, 1)
        XCTAssertTrue(summaries.contains(where: { $0.threadID == threadID && $0.title == "Needs review" && $0.count == 1 }))
    }

    func testTotalPendingApprovalCountIncludesSupplementalThreadBlockers() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        model.permissionRecoveryNotice = AppModel.PermissionRecoveryNotice(
            actionID: "messages.send",
            threadID: threadID,
            target: .automation,
            title: "Messages permission needed",
            message: "Enable automation permissions.",
            remediationSteps: ["Open System Settings"]
        )
        model.syncApprovalPresentationState()

        XCTAssertEqual(model.totalPendingApprovalCount, 1)
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
}
