@testable import CodexChatShared
import CodexKit
import Foundation
import XCTest

@MainActor
final class RuntimeServerRequestContinuityTests: XCTestCase {
    func testServerRequestResolvedClearsPendingUserInputAuthoritatively() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()

        let request = RuntimeUserInputRequest(
            id: 1201,
            method: "item/tool/requestUserInput",
            threadID: "thr_runtime_input",
            turnID: "turn_runtime_input",
            itemID: "item_runtime_input",
            title: "Need clarification",
            prompt: "Share the branch name",
            placeholder: "feature/runtime-contract",
            value: nil,
            options: [],
            detail: "{}"
        )

        model.selectedThreadID = threadID
        model.localThreadIDByRuntimeThreadID["thr_runtime_input"] = threadID

        model.handleRuntimeEvent(.serverRequest(.userInput(request)))

        XCTAssertEqual(model.pendingServerRequestForSelectedThread?.id, request.id)
        XCTAssertEqual(model.activeServerRequest?.id, request.id)

        model.serverRequestResolutionFallbackTasksByRequestID[request.id] = Task<Void, Never> { @MainActor in
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

        XCTAssertNil(model.pendingServerRequestForSelectedThread)
        XCTAssertNil(model.activeServerRequest)
        XCTAssertNil(model.resolvePendingServerRequest(id: request.id))
        XCTAssertNil(model.serverRequestResolutionFallbackTasksByRequestID[request.id])
        XCTAssertEqual(model.serverRequestStatusMessage, "Runtime resolved request \(request.id).")
    }

    func testRuntimeCommunicationFailureResetsPendingServerRequestWithExplicitMessage() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        let projectID = UUID()

        let request = RuntimePermissionsRequest(
            id: 1301,
            method: "item/permissions/requestApproval",
            threadID: "thr_runtime_permissions",
            turnID: "turn_runtime_permissions",
            itemID: "item_runtime_permissions",
            reason: "Need wider filesystem scope",
            cwd: "/tmp",
            permissions: ["filesystem.write"],
            grantRoot: "/tmp/project",
            detail: "{}"
        )

        model.selectedThreadID = threadID
        model.localThreadIDByRuntimeThreadID["thr_runtime_permissions"] = threadID
        model.activeTurnContext = AppModel.ActiveTurnContext(
            localTurnID: UUID(),
            localThreadID: threadID,
            projectID: projectID,
            projectPath: "/tmp/project",
            runtimeThreadID: "thr_runtime_permissions",
            runtimeTurnID: "turn_runtime_permissions",
            memoryWriteMode: .off,
            userText: "continue",
            assistantText: "",
            actions: [],
            startedAt: Date()
        )

        model.handleRuntimeEvent(.serverRequest(.permissions(request)))
        XCTAssertEqual(model.pendingServerRequestForSelectedThread?.id, request.id)

        model.handleRuntimeError(CodexRuntimeError.transportClosed)

        XCTAssertFalse(model.serverRequestStateMachine.hasPendingRequests)
        XCTAssertNil(model.activeServerRequest)
        XCTAssertTrue(model.serverRequestStatusMessage?.contains("Runtime request was reset") ?? false)
        XCTAssertTrue(model.serverRequestStatusMessage?.contains("runtime communication failed") ?? false)

        let entries = model.transcriptStore[threadID, default: []]
        let resetCardExists = entries.contains { entry in
            guard case let .actionCard(card) = entry else {
                return false
            }
            return card.method == "runtime-request/reset" && card.title == "Runtime request reset"
        }
        XCTAssertTrue(resetCardExists)
    }
}
