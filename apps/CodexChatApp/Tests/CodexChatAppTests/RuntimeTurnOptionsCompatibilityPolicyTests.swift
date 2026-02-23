@testable import CodexChatShared
import CodexKit
import XCTest

final class RuntimeTurnOptionsCompatibilityPolicyTests: XCTestCase {
    func testRetriesWhenRuntimeRejectsModelField() {
        let error = CodexRuntimeError.rpcError(
            code: -32602,
            message: "unknown field `model`"
        )

        XCTAssertTrue(RuntimeTurnOptionsCompatibilityPolicy.shouldRetryWithoutTurnOptions(for: error))
    }

    func testRetriesWhenReasoningEffortIsUnsupported() {
        let error = CodexRuntimeError.invalidResponse("unsupported value for reasoning.effort")

        XCTAssertTrue(RuntimeTurnOptionsCompatibilityPolicy.shouldRetryWithoutTurnOptions(for: error))
    }

    func testDoesNotRetryForUnrelatedRuntimeErrors() {
        let error = CodexRuntimeError.rpcError(
            code: -32602,
            message: "unknown field `cwd`"
        )

        XCTAssertFalse(RuntimeTurnOptionsCompatibilityPolicy.shouldRetryWithoutTurnOptions(for: error))
    }
}
