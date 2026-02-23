@testable import CodexChatShared
import CodexKit
import XCTest

@MainActor
final class RuntimeTurnOptionsFallbackTests: XCTestCase {
    func testShouldRetryWithoutTurnOptionsWhenRuntimeRejectsModelField() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let error = CodexRuntimeError.rpcError(
            code: -32602,
            message: "unknown field `model`"
        )

        XCTAssertTrue(model.shouldRetryWithoutTurnOptions(error))
    }

    func testShouldRetryWithoutTurnOptionsWhenReasoningEffortIsUnsupported() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let error = CodexRuntimeError.invalidResponse("unsupported value for reasoning.effort")

        XCTAssertTrue(model.shouldRetryWithoutTurnOptions(error))
    }

    func testShouldNotRetryWithoutTurnOptionsForUnrelatedRuntimeErrors() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let error = CodexRuntimeError.rpcError(
            code: -32602,
            message: "unknown field `cwd`"
        )

        XCTAssertFalse(model.shouldRetryWithoutTurnOptions(error))
    }
}
