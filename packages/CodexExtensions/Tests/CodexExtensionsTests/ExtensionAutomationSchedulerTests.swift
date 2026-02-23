@testable import CodexExtensions
import Foundation
import XCTest

final class ExtensionAutomationSchedulerTests: XCTestCase {
    func testSchedulerAppliesRetryBackoffAfterFailure() async throws {
        let probe = SchedulerProbe(handlerResults: [false, false], stopAfterSleepCalls: 3)
        let scheduler = makeScheduler(probe: probe)

        await scheduler.replaceAutomations([makeAutomation(id: "retry-once")]) { automation in
            await probe.recordHandlerCall(id: automation.id)
            return await probe.nextHandlerResult()
        }

        try await eventually(timeoutSeconds: 1.0) {
            await probe.sleepCallCount >= 3
        }
        await scheduler.stopAll()

        let backoffSeconds = await probe.backoffSeconds(lessThan: 300)
        let handlerCallCount = await probe.handlerCallCount
        XCTAssertEqual(backoffSeconds, [30])
        XCTAssertEqual(handlerCallCount, 2)
    }

    func testSchedulerResetsBackoffAfterSuccessfulRetry() async throws {
        let probe = SchedulerProbe(handlerResults: [false, true, false, true], stopAfterSleepCalls: 5)
        let scheduler = makeScheduler(probe: probe)

        await scheduler.replaceAutomations([makeAutomation(id: "retry-reset")]) { automation in
            await probe.recordHandlerCall(id: automation.id)
            return await probe.nextHandlerResult()
        }

        try await eventually(timeoutSeconds: 1.0) {
            await probe.sleepCallCount >= 5
        }
        await scheduler.stopAll()

        let backoffSeconds = await probe.backoffSeconds(lessThan: 300)
        let handlerCallCount = await probe.handlerCallCount
        XCTAssertEqual(backoffSeconds, [30, 30])
        XCTAssertEqual(handlerCallCount, 4)
    }

    private func makeScheduler(probe: SchedulerProbe) -> ExtensionAutomationScheduler {
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let fixedDate = Date(timeIntervalSince1970: 1_769_184_000) // 2026-01-01T00:00:00Z

        return ExtensionAutomationScheduler(
            timeZone: utc,
            now: { fixedDate },
            sleep: { nanoseconds in
                await probe.recordSleep(nanoseconds)
                if await probe.shouldStop {
                    throw CancellationError()
                }
            }
        )
    }

    private func makeAutomation(id: String) -> ExtensionAutomationDefinition {
        ExtensionAutomationDefinition(
            id: id,
            schedule: "*/5 * * * *",
            handler: .init(command: ["/bin/echo", "ok"])
        )
    }

    private func eventually(
        timeoutSeconds: TimeInterval,
        condition: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
            await Task.yield()
        }
        throw XCTestError(.failureWhileWaiting)
    }
}

private actor SchedulerProbe {
    private var sleeps: [UInt64] = []
    private var pendingHandlerResults: [Bool]
    private(set) var handlerCallIDs: [String] = []
    private let stopAfterSleepCalls: Int

    init(handlerResults: [Bool], stopAfterSleepCalls: Int) {
        pendingHandlerResults = handlerResults
        self.stopAfterSleepCalls = stopAfterSleepCalls
    }

    var sleepCallCount: Int {
        sleeps.count
    }

    var handlerCallCount: Int {
        handlerCallIDs.count
    }

    var shouldStop: Bool {
        sleeps.count >= stopAfterSleepCalls
    }

    func recordSleep(_ nanoseconds: UInt64) {
        sleeps.append(nanoseconds)
    }

    func recordHandlerCall(id: String) {
        handlerCallIDs.append(id)
    }

    func nextHandlerResult() -> Bool {
        guard !pendingHandlerResults.isEmpty else {
            return false
        }
        return pendingHandlerResults.removeFirst()
    }

    func backoffSeconds(lessThan scheduleSeconds: UInt64) -> [Int] {
        sleeps
            .map { Int($0 / 1_000_000_000) }
            .filter { $0 > 0 && UInt64($0) < scheduleSeconds }
    }
}
