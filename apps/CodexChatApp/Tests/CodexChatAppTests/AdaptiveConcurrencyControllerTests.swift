@testable import CodexChatShared
import XCTest

final class AdaptiveConcurrencyControllerTests: XCTestCase {
    func testControllerScalesUpWithBacklogOnHealthyWorkers() async {
        let controller = AdaptiveConcurrencyController(minimumLimit: 2, hardMaximumLimit: 64)

        let first = await controller.nextLimit(
            signals: .init(
                queuedTurns: 0,
                activeTurns: 0,
                workerCount: 2,
                degradedWorkerCount: 0,
                totalWorkerFailures: 0,
                selectedThreadIsActive: false,
                memoryPressure: false
            )
        )
        let second = await controller.nextLimit(
            signals: .init(
                queuedTurns: 24,
                activeTurns: 4,
                workerCount: 2,
                degradedWorkerCount: 0,
                totalWorkerFailures: 0,
                selectedThreadIsActive: true,
                memoryPressure: false
            )
        )

        XCTAssertGreaterThanOrEqual(second, first)
    }

    func testControllerScalesDownUnderPressure() async {
        let controller = AdaptiveConcurrencyController(minimumLimit: 2, hardMaximumLimit: 64)

        _ = await controller.nextLimit(
            signals: .init(
                queuedTurns: 32,
                activeTurns: 8,
                workerCount: 4,
                degradedWorkerCount: 0,
                totalWorkerFailures: 0,
                selectedThreadIsActive: false,
                memoryPressure: false
            )
        )
        let pressured = await controller.nextLimit(
            signals: .init(
                queuedTurns: 32,
                activeTurns: 8,
                workerCount: 4,
                degradedWorkerCount: 2,
                totalWorkerFailures: 3,
                selectedThreadIsActive: false,
                memoryPressure: true
            )
        )

        XCTAssertLessThanOrEqual(pressured, 32)
        XCTAssertGreaterThanOrEqual(pressured, 2)
    }
}
