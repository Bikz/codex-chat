@testable import CodexChatShared
import Foundation
import XCTest

final class ParallelTurnSchedulingTests: XCTestCase {
    func testTurnConcurrencySchedulerPrioritizesSelectedThread() async throws {
        let scheduler = TurnConcurrencyScheduler(maxConcurrentTurns: 1)
        let firstThreadID = UUID()
        let queuedAutoThreadID = UUID()
        let selectedThreadID = UUID()
        let order = EventOrderRecorder()

        try await scheduler.reserve(threadID: firstThreadID, priority: .manual)

        let queuedAutoWaiter = Task {
            try await scheduler.reserve(threadID: queuedAutoThreadID, priority: .queuedAuto)
            await order.append(queuedAutoThreadID)
        }
        let selectedWaiter = Task {
            try await scheduler.reserve(threadID: selectedThreadID, priority: .selected)
            await order.append(selectedThreadID)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        await scheduler.release(threadID: firstThreadID)

        try await eventually(timeoutSeconds: 1.0) {
            let values = await order.values()
            return values.first == selectedThreadID
        }

        await scheduler.release(threadID: selectedThreadID)

        try await eventually(timeoutSeconds: 1.0) {
            let values = await order.values()
            return values == [selectedThreadID, queuedAutoThreadID]
        }

        await scheduler.release(threadID: queuedAutoThreadID)
        _ = try await (queuedAutoWaiter.value, selectedWaiter.value)
    }

    func testTurnConcurrencySchedulerScalesAcrossParallelSessionCounts() async throws {
        for sessionCount in [1, 5, 10, 25, 50] {
            let scheduler = TurnConcurrencyScheduler(maxConcurrentTurns: sessionCount)
            let completionCounter = CompletionCounter()
            let threadIDs = (0 ..< sessionCount).map { _ in UUID() }

            try await withThrowingTaskGroup(of: Void.self) { group in
                for threadID in threadIDs {
                    group.addTask {
                        try await scheduler.reserve(threadID: threadID, priority: .manual)
                        await completionCounter.increment()
                    }
                }
                try await group.waitForAll()
            }

            let completedCount = await completionCounter.value()
            XCTAssertEqual(
                completedCount,
                sessionCount,
                "Expected all \(sessionCount) sessions to reserve without starvation."
            )

            for threadID in threadIDs {
                await scheduler.release(threadID: threadID)
            }
        }
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

private actor CompletionCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private actor EventOrderRecorder {
    private var events: [UUID] = []

    func append(_ threadID: UUID) {
        events.append(threadID)
    }

    func values() -> [UUID] {
        events
    }
}
