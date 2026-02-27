@testable import CodexChatShared
import XCTest

final class AdaptiveConcurrencyControllerTests: XCTestCase {
    func testControllerScalesUpWithBacklogOnHealthyWorkers() async {
        let controller = AdaptiveConcurrencyController(
            minimumLimit: 2,
            hardMaximumLimit: 64,
            basePerWorker: 3
        )

        let first = await controller.nextLimit(
            signals: .init(
                queuedTurns: 0,
                workerQueuedTurns: 0,
                activeTurns: 0,
                workerCount: 2,
                degradedWorkerCount: 0,
                totalWorkerFailures: 0,
                selectedThreadIsActive: false,
                memoryPressure: false,
                rollingP95TTFTMS: nil,
                eventBacklogPressure: false
            )
        )
        let second = await controller.nextLimit(
            signals: .init(
                queuedTurns: 24,
                workerQueuedTurns: 0,
                activeTurns: 4,
                workerCount: 2,
                degradedWorkerCount: 0,
                totalWorkerFailures: 0,
                selectedThreadIsActive: true,
                memoryPressure: false,
                rollingP95TTFTMS: nil,
                eventBacklogPressure: false
            )
        )

        XCTAssertGreaterThanOrEqual(second, first)
    }

    func testControllerScalesDownUnderPressure() async {
        let controller = AdaptiveConcurrencyController(
            minimumLimit: 2,
            hardMaximumLimit: 64,
            basePerWorker: 4
        )

        _ = await controller.nextLimit(
            signals: .init(
                queuedTurns: 32,
                workerQueuedTurns: 0,
                activeTurns: 8,
                workerCount: 4,
                degradedWorkerCount: 0,
                totalWorkerFailures: 0,
                selectedThreadIsActive: false,
                memoryPressure: false,
                rollingP95TTFTMS: nil,
                eventBacklogPressure: false
            )
        )
        let pressured = await controller.nextLimit(
            signals: .init(
                queuedTurns: 32,
                workerQueuedTurns: 8,
                activeTurns: 8,
                workerCount: 4,
                degradedWorkerCount: 2,
                totalWorkerFailures: 3,
                selectedThreadIsActive: false,
                memoryPressure: true,
                rollingP95TTFTMS: 3000,
                eventBacklogPressure: true
            )
        )

        XCTAssertLessThanOrEqual(pressured, 24)
        XCTAssertGreaterThanOrEqual(pressured, 2)
    }

    func testControllerRespondsToTTFTPressure() async {
        let controller = AdaptiveConcurrencyController(
            minimumLimit: 2,
            hardMaximumLimit: 64,
            basePerWorker: 4,
            ttftBudgetMS: 2000
        )

        let warm = await controller.nextLimit(
            signals: .init(
                queuedTurns: 24,
                workerQueuedTurns: 0,
                activeTurns: 6,
                workerCount: 4,
                degradedWorkerCount: 0,
                totalWorkerFailures: 0,
                selectedThreadIsActive: false,
                memoryPressure: false,
                rollingP95TTFTMS: 1100,
                eventBacklogPressure: false
            )
        )
        let throttled = await controller.nextLimit(
            signals: .init(
                queuedTurns: 24,
                workerQueuedTurns: 0,
                activeTurns: 6,
                workerCount: 4,
                degradedWorkerCount: 0,
                totalWorkerFailures: 0,
                selectedThreadIsActive: false,
                memoryPressure: false,
                rollingP95TTFTMS: 3200,
                eventBacklogPressure: false
            )
        )

        XCTAssertLessThan(throttled, warm)
    }

    func testControllerRespondsToWorkerQueuePressure() async {
        let controller = AdaptiveConcurrencyController(
            minimumLimit: 2,
            hardMaximumLimit: 64,
            basePerWorker: 5
        )

        let warm = await controller.nextLimit(
            signals: .init(
                queuedTurns: 8,
                workerQueuedTurns: 0,
                activeTurns: 8,
                workerCount: 4,
                degradedWorkerCount: 0,
                totalWorkerFailures: 0,
                selectedThreadIsActive: false,
                memoryPressure: false,
                rollingP95TTFTMS: 1200,
                eventBacklogPressure: false
            )
        )
        let queued = await controller.nextLimit(
            signals: .init(
                queuedTurns: 8,
                workerQueuedTurns: 16,
                activeTurns: 8,
                workerCount: 4,
                degradedWorkerCount: 0,
                totalWorkerFailures: 0,
                selectedThreadIsActive: false,
                memoryPressure: false,
                rollingP95TTFTMS: 1200,
                eventBacklogPressure: false
            )
        )

        XCTAssertLessThan(queued, warm)
        XCTAssertGreaterThanOrEqual(queued, 2)
    }
}
