@testable import CodexChatShared
import Foundation
import XCTest

final class RuntimePerformanceSignalsTests: XCTestCase {
    func testComputesRollingP95TTFT() async {
        let signals = RuntimePerformanceSignals(maxSampleCount: 32)
        let threadID = UUID()

        for index in 0 ..< 20 {
            let startedAt = Date().addingTimeInterval(-Double(index + 1))
            await signals.recordDispatchStart(
                threadID: threadID,
                localTurnID: UUID(),
                startedAt: startedAt
            )
            await signals.recordFirstTokenIfNeeded(
                threadID: threadID,
                receivedAt: startedAt.addingTimeInterval(Double(index + 1) * 0.1)
            )
        }

        let snapshot = await signals.snapshot()
        XCTAssertEqual(snapshot.sampleCount, 20)
        XCTAssertNotNil(snapshot.rollingP95TTFTMS)
        XCTAssertGreaterThan(snapshot.rollingP95TTFTMS ?? 0, 0)
    }

    func testFirstTokenIsIgnoredWithoutDispatchStart() async {
        let signals = RuntimePerformanceSignals()
        await signals.recordFirstTokenIfNeeded(threadID: UUID())
        let snapshot = await signals.snapshot()
        XCTAssertEqual(snapshot.sampleCount, 0)
        XCTAssertNil(snapshot.rollingP95TTFTMS)
    }

    func testCompletionClearsPendingDispatchWithoutSample() async {
        let signals = RuntimePerformanceSignals()
        let threadID = UUID()
        await signals.recordDispatchStart(threadID: threadID, localTurnID: UUID(), startedAt: Date())
        await signals.markTurnCompleted(threadID: threadID)
        await signals.recordFirstTokenIfNeeded(threadID: threadID)
        let snapshot = await signals.snapshot()
        XCTAssertEqual(snapshot.sampleCount, 0)
    }
}
