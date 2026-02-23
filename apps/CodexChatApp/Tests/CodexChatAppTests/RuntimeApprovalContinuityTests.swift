@testable import CodexChatShared
import CodexKit
import Foundation
import XCTest

@MainActor
final class RuntimeApprovalContinuityTests: XCTestCase {
    func testRuntimeCommunicationFailureResetsPendingApprovalWithExplicitMessage() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        let projectID = UUID()

        let request = RuntimeApprovalRequest(
            id: 701,
            kind: .commandExecution,
            method: "item/commandExecution/requestApproval",
            threadID: "thr_runtime_error",
            turnID: "turn_runtime_error",
            itemID: "item_runtime_error",
            reason: "needs confirmation",
            risk: nil,
            cwd: "/tmp",
            command: ["echo", "hello"],
            changes: [],
            detail: "{}"
        )

        model.selectedThreadID = threadID
        model.localThreadIDByRuntimeThreadID["thr_runtime_error"] = threadID
        model.activeTurnContext = AppModel.ActiveTurnContext(
            localTurnID: UUID(),
            localThreadID: threadID,
            projectID: projectID,
            projectPath: "/tmp",
            runtimeThreadID: "thr_runtime_error",
            runtimeTurnID: "turn_runtime_error",
            memoryWriteMode: .off,
            userText: "hello",
            assistantText: "",
            actions: [],
            startedAt: Date()
        )
        model.approvalStateMachine.enqueue(request, threadID: threadID)
        model.syncApprovalPresentationState()
        model.isApprovalDecisionInProgress = true

        model.handleRuntimeError(CodexRuntimeError.transportClosed)

        XCTAssertFalse(model.approvalStateMachine.hasPendingApprovals)
        XCTAssertNil(model.activeApprovalRequest)
        XCTAssertFalse(model.isApprovalDecisionInProgress)
        XCTAssertTrue(model.approvalStatusMessage?.contains("Approval request was reset") ?? false)
        XCTAssertTrue(model.approvalStatusMessage?.contains("runtime communication failed") ?? false)

        let entries = model.transcriptStore[threadID, default: []]
        let approvalResetCardExists = entries.contains { entry in
            guard case let .actionCard(card) = entry else {
                return false
            }
            return card.method == "approval/reset" && card.title == "Approval reset"
        }
        XCTAssertTrue(approvalResetCardExists)
    }
}
