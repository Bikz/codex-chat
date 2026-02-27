@testable import CodexChatShared
import XCTest

final class AdaptiveConcurrencyRefreshStateTests: XCTestCase {
    func testScheduleStartsTaskWhenIdle() {
        var state = AdaptiveConcurrencyRefreshState()

        let generation = state.schedule(reason: "first")

        XCTAssertEqual(generation, 1)
        XCTAssertEqual(state.generation, 1)
        XCTAssertEqual(state.latestReason, "first")
        XCTAssertTrue(state.isTaskRunning)
    }

    func testScheduleWhileRunningCoalescesWithoutStartingSecondTask() {
        var state = AdaptiveConcurrencyRefreshState()
        _ = state.schedule(reason: "first")

        let secondGeneration = state.schedule(reason: "second")

        XCTAssertNil(secondGeneration)
        XCTAssertEqual(state.generation, 2)
        XCTAssertEqual(state.latestReason, "second")
        XCTAssertTrue(state.isTaskRunning)
    }

    func testReadyReasonOnlyForLatestGeneration() {
        var state = AdaptiveConcurrencyRefreshState()
        let firstGeneration = state.schedule(reason: "first")
        _ = state.schedule(reason: "second")

        XCTAssertNil(state.refreshReasonIfReady(for: firstGeneration ?? 0))
        XCTAssertEqual(state.refreshReasonIfReady(for: state.generation), "second")

        state.markIdle()
        XCTAssertFalse(state.isTaskRunning)
    }
}
