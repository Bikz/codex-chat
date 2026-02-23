@testable import CodexChatShared
import CodexKit
import XCTest

@MainActor
final class RuntimeStaleThreadRecoveryPolicyTests: XCTestCase {
    func testShouldRecreateRuntimeThreadForUnknownThreadRPCError() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let error = CodexRuntimeError.rpcError(
            code: -32010,
            message: "unknown threadId: thr_stale"
        )

        XCTAssertTrue(model.shouldRecreateRuntimeThread(after: error))
    }

    func testShouldRecreateRuntimeThreadForMissingThreadInvalidResponse() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let error = CodexRuntimeError.invalidResponse("Thread missing for turn/start")

        XCTAssertTrue(model.shouldRecreateRuntimeThread(after: error))
    }

    func testShouldNotRecreateRuntimeThreadForUnrelatedRuntimeError() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let error = CodexRuntimeError.rpcError(
            code: -32603,
            message: "unknown field `approvalPolicy`"
        )

        XCTAssertFalse(model.shouldRecreateRuntimeThread(after: error))
    }

    func testStaleRuntimeThreadRecreateRetryPolicyAllowsExactlyOneRetryByDefault() {
        XCTAssertTrue(AppModel.shouldRetryStaleRuntimeThreadRecreation(retryCount: 0))
        XCTAssertFalse(AppModel.shouldRetryStaleRuntimeThreadRecreation(retryCount: 1))
    }
}
