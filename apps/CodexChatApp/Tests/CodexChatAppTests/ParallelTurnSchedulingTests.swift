@testable import CodexChatShared
import Foundation
import XCTest

final class ParallelTurnSchedulingTests: XCTestCase {
    @MainActor
    func testDefaultMaxConcurrentTurnsSupportsLargeParallelWorkloads() {
        let defaultLimit = AppModel.defaultMaxConcurrentTurns
        XCTAssertGreaterThanOrEqual(defaultLimit, 32)
    }

    @MainActor
    func testDefaultMaxConcurrentTurnsHonorsEnvironmentOverride() {
        let key = "CODEXCHAT_MAX_PARALLEL_TURNS"
        let previousValue = ProcessInfo.processInfo.environment[key]
        setenv(key, "73", 1)
        defer {
            if let previousValue {
                setenv(key, previousValue, 1)
            } else {
                unsetenv(key)
            }
        }

        let configuredLimit = AppModel.defaultMaxConcurrentTurns
        XCTAssertEqual(configuredLimit, 73)
    }

    @MainActor
    func testRuntimeEventTraceSampleRateHonorsEnvironmentOverride() {
        let key = "CODEXCHAT_RUNTIME_EVENT_TRACE_SAMPLE_RATE"
        let previousValue = ProcessInfo.processInfo.environment[key]
        setenv(key, "9", 1)
        defer {
            if let previousValue {
                setenv(key, previousValue, 1)
            } else {
                unsetenv(key)
            }
        }

        XCTAssertEqual(AppModel.runtimeEventTraceSampleRate, 9)
    }

    @MainActor
    func testDefaultRuntimePoolSizeHonorsEnvironmentOverride() {
        let key = "CODEXCHAT_RUNTIME_POOL_SIZE"
        let previousValue = ProcessInfo.processInfo.environment[key]
        setenv(key, "5", 1)
        defer {
            if let previousValue {
                setenv(key, previousValue, 1)
            } else {
                unsetenv(key)
            }
        }

        XCTAssertEqual(AppModel.defaultRuntimePoolSize, 5)
    }

    @MainActor
    func testActiveRuntimePoolSizeDefaultsToConfiguredSizeWithoutFlags() {
        let sizeKey = "CODEXCHAT_RUNTIME_POOL_SIZE"
        let previousSize = ProcessInfo.processInfo.environment[sizeKey]
        setenv(sizeKey, "4", 1)
        defer {
            if let previousSize {
                setenv(sizeKey, previousSize, 1)
            } else {
                unsetenv(sizeKey)
            }
        }

        XCTAssertEqual(AppModel.activeRuntimePoolSize, 4)
    }

    @MainActor
    func testActiveRuntimePoolSizeClampsToAtLeastTwoWorkers() {
        let sizeKey = "CODEXCHAT_RUNTIME_POOL_SIZE"
        let previousSize = ProcessInfo.processInfo.environment[sizeKey]
        setenv(sizeKey, "1", 1)
        defer {
            if let previousSize {
                setenv(sizeKey, previousSize, 1)
            } else {
                unsetenv(sizeKey)
            }
        }

        XCTAssertEqual(AppModel.activeRuntimePoolSize, 2)
    }

    @MainActor
    func testLegacyShardingFlagsDoNotDisablePoolSharding() {
        let shardingKey = "CODEXCHAT_RUNTIME_POOL_ENABLE_SHARDING"
        let disableKey = "CODEXCHAT_RUNTIME_POOL_DISABLE_SHARDING"
        let sizeKey = "CODEXCHAT_RUNTIME_POOL_SIZE"
        let previousSharding = ProcessInfo.processInfo.environment[shardingKey]
        let previousDisable = ProcessInfo.processInfo.environment[disableKey]
        let previousSize = ProcessInfo.processInfo.environment[sizeKey]
        setenv(shardingKey, "0", 1)
        setenv(disableKey, "1", 1)
        setenv(sizeKey, "4", 1)
        defer {
            if let previousSharding {
                setenv(shardingKey, previousSharding, 1)
            } else {
                unsetenv(shardingKey)
            }
            if let previousDisable {
                setenv(disableKey, previousDisable, 1)
            } else {
                unsetenv(disableKey)
            }
            if let previousSize {
                setenv(sizeKey, previousSize, 1)
            } else {
                unsetenv(sizeKey)
            }
        }

        XCTAssertEqual(AppModel.activeRuntimePoolSize, 4)
    }

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

    func testTurnConcurrencySchedulerPromotesWaiterAfterLimitIncrease() async throws {
        let scheduler = TurnConcurrencyScheduler(maxConcurrentTurns: 1)
        let firstThreadID = UUID()
        let secondThreadID = UUID()
        let order = EventOrderRecorder()

        try await scheduler.reserve(threadID: firstThreadID, priority: .manual)
        let waiter = Task {
            try await scheduler.reserve(threadID: secondThreadID, priority: .manual)
            await order.append(secondThreadID)
        }

        try await Task.sleep(nanoseconds: 40_000_000)
        await scheduler.updateMaxConcurrentTurns(2)

        try await eventually(timeoutSeconds: 1.0) {
            await order.values() == [secondThreadID]
        }

        await scheduler.release(threadID: secondThreadID)
        await scheduler.release(threadID: firstThreadID)
        _ = try await waiter.value
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
