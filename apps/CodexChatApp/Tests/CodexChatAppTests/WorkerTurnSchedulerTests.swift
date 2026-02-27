@testable import CodexChatShared
import Foundation
import XCTest

final class WorkerTurnSchedulerTests: XCTestCase {
    func testPerWorkerCapAppliesIndependently() async throws {
        let scheduler = WorkerTurnScheduler(maxConcurrentTurnsPerWorker: 1)
        let workerA = RuntimePoolWorkerID(1)
        let workerB = RuntimePoolWorkerID(2)
        let grantedWorkers = WorkerGrantRecorder()

        try await scheduler.reserve(workerID: workerA)

        let blockedA = Task {
            try await scheduler.reserve(workerID: workerA)
            await grantedWorkers.append(workerA)
        }
        let independentB = Task {
            try await scheduler.reserve(workerID: workerB)
            await grantedWorkers.append(workerB)
        }

        try await eventually(timeoutSeconds: 1.0) {
            let snapshot = await scheduler.snapshot()
            return snapshot[workerA]?.activePermits == 1
                && snapshot[workerA]?.queueDepth == 1
                && snapshot[workerB]?.activePermits == 1
        }

        await scheduler.release(workerID: workerA)

        try await eventually(timeoutSeconds: 1.0) {
            let values = await grantedWorkers.values()
            return values.contains(workerA) && values.contains(workerB)
        }

        await scheduler.release(workerID: workerA)
        await scheduler.release(workerID: workerB)
        _ = try await (blockedA.value, independentB.value)
    }

    func testCancellationRemovesQueuedWaiter() async throws {
        let scheduler = WorkerTurnScheduler(maxConcurrentTurnsPerWorker: 1)
        let workerID = RuntimePoolWorkerID(3)

        try await scheduler.reserve(workerID: workerID)
        let waiter = Task {
            try await scheduler.reserve(workerID: workerID)
        }

        try await eventually(timeoutSeconds: 1.0) {
            let snapshot = await scheduler.snapshot()
            return snapshot[workerID]?.queueDepth == 1
                && snapshot[workerID]?.activePermits == 1
        }

        waiter.cancel()
        do {
            try await waiter.value
            XCTFail("Expected waiter cancellation to throw.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        try await eventually(timeoutSeconds: 1.0) {
            let snapshot = await scheduler.snapshot()
            return snapshot[workerID]?.queueDepth == 0
                && snapshot[workerID]?.activePermits == 1
        }

        await scheduler.release(workerID: workerID)

        try await eventually(timeoutSeconds: 1.0) {
            let snapshot = await scheduler.snapshot()
            return snapshot[workerID] == nil
        }
    }

    func testFIFOOrderingWithinWorker() async throws {
        let scheduler = WorkerTurnScheduler(maxConcurrentTurnsPerWorker: 1)
        let workerID = RuntimePoolWorkerID(4)
        let order = IntegerRecorder()

        try await scheduler.reserve(workerID: workerID)

        let firstWaiter = Task {
            try await scheduler.reserve(workerID: workerID)
            await order.append(1)
        }
        let secondWaiter = Task {
            try await scheduler.reserve(workerID: workerID)
            await order.append(2)
        }

        try await Task.sleep(nanoseconds: 40_000_000)
        await scheduler.release(workerID: workerID)

        try await eventually(timeoutSeconds: 1.0) {
            await order.values() == [1]
        }

        await scheduler.release(workerID: workerID)

        try await eventually(timeoutSeconds: 1.0) {
            await order.values() == [1, 2]
        }

        await scheduler.release(workerID: workerID)
        _ = try await (firstWaiter.value, secondWaiter.value)
    }

    func testCancelAllResumesQueuedWaitersAndClearsMetrics() async throws {
        let scheduler = WorkerTurnScheduler(maxConcurrentTurnsPerWorker: 1)
        let workerID = RuntimePoolWorkerID(5)

        try await scheduler.reserve(workerID: workerID)

        let waiterOne = Task {
            try await scheduler.reserve(workerID: workerID)
        }
        let waiterTwo = Task {
            try await scheduler.reserve(workerID: workerID)
        }

        try await eventually(timeoutSeconds: 1.0) {
            let snapshot = await scheduler.snapshot()
            return snapshot[workerID]?.activePermits == 1
                && snapshot[workerID]?.queueDepth == 2
        }

        await scheduler.cancelAll()

        do {
            try await waiterOne.value
            XCTFail("Expected waiterOne to throw CancellationError after cancelAll.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        do {
            try await waiterTwo.value
            XCTFail("Expected waiterTwo to throw CancellationError after cancelAll.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let snapshot = await scheduler.snapshot()
        XCTAssertTrue(snapshot.isEmpty)
    }

    private func eventually(timeoutSeconds: TimeInterval, condition: @escaping () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw XCTestError(.failureWhileWaiting)
    }
}

private actor WorkerGrantRecorder {
    private var entries: [RuntimePoolWorkerID] = []

    func append(_ workerID: RuntimePoolWorkerID) {
        entries.append(workerID)
    }

    func values() -> [RuntimePoolWorkerID] {
        entries
    }
}

private actor IntegerRecorder {
    private var entries: [Int] = []

    func append(_ value: Int) {
        entries.append(value)
    }

    func values() -> [Int] {
        entries
    }
}
