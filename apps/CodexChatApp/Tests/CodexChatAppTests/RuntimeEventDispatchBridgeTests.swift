@testable import CodexChatShared
import CodexKit
import XCTest

final class RuntimeEventDispatchBridgeTests: XCTestCase {
    func testCoalescesAdjacentAssistantDeltas() async {
        let recorder = RuntimeEventBatchRecorder()
        let bridge = RuntimeEventDispatchBridge { events in
            await recorder.record(events)
        }

        await bridge.enqueue(.assistantMessageDelta(threadID: "thr", turnID: "turn", itemID: "item", delta: "Hel"))
        await bridge.enqueue(.assistantMessageDelta(threadID: "thr", turnID: "turn", itemID: "item", delta: "lo"))
        await bridge.flushNow()

        let events = await recorder.allEvents()
        XCTAssertEqual(events.count, 1)
        guard case let .assistantMessageDelta(threadID, turnID, itemID, delta) = events[0] else {
            XCTFail("Expected assistant delta event.")
            return
        }

        XCTAssertEqual(threadID, "thr")
        XCTAssertEqual(turnID, "turn")
        XCTAssertEqual(itemID, "item")
        XCTAssertEqual(delta, "Hello")
    }

    func testAssistantDeltasDoNotCoalesceAcrossActionBoundary() async {
        let recorder = RuntimeEventBatchRecorder()
        let bridge = RuntimeEventDispatchBridge { events in
            await recorder.record(events)
        }

        await bridge.enqueue(.assistantMessageDelta(threadID: "thr", turnID: "turn", itemID: "item", delta: "A"))
        await bridge.enqueue(
            .action(
                RuntimeAction(
                    method: "runtime/stderr",
                    itemID: nil,
                    itemType: nil,
                    threadID: "thr",
                    turnID: "turn",
                    title: "Runtime stderr",
                    detail: "warn"
                )
            )
        )
        await bridge.enqueue(.assistantMessageDelta(threadID: "thr", turnID: "turn", itemID: "item", delta: "B"))
        await bridge.flushNow()

        let events = await recorder.allEvents()
        XCTAssertEqual(events.count, 3)
    }

    func testCoalescesAdjacentCommandOutputDeltas() async {
        let recorder = RuntimeEventBatchRecorder()
        let bridge = RuntimeEventDispatchBridge { events in
            await recorder.record(events)
        }

        await bridge.enqueue(
            .commandOutputDelta(
                RuntimeCommandOutputDelta(
                    itemID: "cmd",
                    threadID: "thr",
                    turnID: "turn",
                    delta: "foo"
                )
            )
        )
        await bridge.enqueue(
            .commandOutputDelta(
                RuntimeCommandOutputDelta(
                    itemID: "cmd",
                    threadID: "thr",
                    turnID: "turn",
                    delta: "bar"
                )
            )
        )
        await bridge.flushNow()

        let events = await recorder.allEvents()
        XCTAssertEqual(events.count, 1)
        guard case let .commandOutputDelta(delta) = events[0] else {
            XCTFail("Expected command output delta event.")
            return
        }
        XCTAssertEqual(delta.delta, "foobar")
        XCTAssertEqual(delta.itemID, "cmd")
    }
}

private actor RuntimeEventBatchRecorder {
    private var batches: [[CodexRuntimeEvent]] = []

    func record(_ batch: [CodexRuntimeEvent]) {
        batches.append(batch)
    }

    func allEvents() -> [CodexRuntimeEvent] {
        batches.flatMap(\.self)
    }
}
