@testable import CodexChatShared
import Foundation
import XCTest

@MainActor
final class ConversationUpdateSchedulerTests: XCTestCase {
    func testFlushImmediatelyPreservesPerItemOrderAndText() {
        var flushedBatches: [[ConversationUpdateScheduler.BatchItem]] = []
        let scheduler = ConversationUpdateScheduler { batch in
            flushedBatches.append(batch)
        }

        let threadID = UUID()
        scheduler.enqueue(delta: "Hel", threadID: threadID, itemID: "item-a")
        scheduler.enqueue(delta: "lo", threadID: threadID, itemID: "item-a")
        scheduler.enqueue(delta: "!", threadID: threadID, itemID: "item-b")

        scheduler.flushImmediately()

        XCTAssertEqual(flushedBatches.count, 1)
        XCTAssertEqual(
            flushedBatches.first,
            [
                .init(threadID: threadID, itemID: "item-a", delta: "Hello"),
                .init(threadID: threadID, itemID: "item-b", delta: "!"),
            ]
        )
    }

    func testAdaptiveIntervalWidensUnderBurstAndRecovers() async {
        let scheduler = ConversationUpdateScheduler { _ in }
        let threadID = UUID()
        let burst = String(repeating: "x", count: 4_200)

        scheduler.enqueue(delta: burst, threadID: threadID, itemID: "item-a")
        XCTAssertEqual(scheduler.currentFlushIntervalMilliseconds, 50)

        scheduler.flushImmediately()
        XCTAssertEqual(scheduler.currentFlushIntervalMilliseconds, 50)

        try? await Task.sleep(nanoseconds: 1_100_000_000)
        scheduler.enqueue(delta: "ok", threadID: threadID, itemID: "item-b")

        XCTAssertEqual(scheduler.currentFlushIntervalMilliseconds, 33)
    }
}
