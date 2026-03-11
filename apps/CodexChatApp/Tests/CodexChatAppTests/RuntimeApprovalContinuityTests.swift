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

    func testServerRequestResolvedClearsPendingApprovalAuthoritatively() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()

        let request = RuntimeApprovalRequest(
            id: 901,
            kind: .commandExecution,
            method: "item/commandExecution/requestApproval",
            threadID: "thr_runtime_resolved",
            turnID: "turn_runtime_resolved",
            itemID: "item_runtime_resolved",
            reason: "needs confirmation",
            risk: nil,
            cwd: "/tmp",
            command: ["echo", "hello"],
            changes: [],
            detail: "{}"
        )

        model.selectedThreadID = threadID
        model.localThreadIDByRuntimeThreadID["thr_runtime_resolved"] = threadID
        model.approvalStateMachine.enqueue(request, threadID: threadID)
        model.syncApprovalPresentationState()
        model.approvalResolutionFallbackTasksByRequestID[request.id] = Task<Void, Never> { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
        }

        model.handleRuntimeEvent(
            .serverRequestResolved(
                RuntimeServerRequestResolution(
                    requestID: request.id,
                    method: request.method,
                    threadID: request.threadID,
                    turnID: request.turnID,
                    itemID: request.itemID,
                    detail: "{}"
                )
            )
        )

        XCTAssertFalse(model.approvalStateMachine.hasPendingApprovals)
        XCTAssertNil(model.activeApprovalRequest)
        XCTAssertNil(model.resolvePendingApprovalRequest(id: request.id))
        XCTAssertNil(model.approvalResolutionFallbackTasksByRequestID[request.id])
        XCTAssertEqual(model.approvalStatusMessage, "Runtime resolved request \(request.id).")
    }
}
