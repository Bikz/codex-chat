@testable import CodexChatShared
import CodexKit
import XCTest

final class RuntimeEventDispatchBridgeTests: XCTestCase {
    func testCoalescesAdjacentAssistantDeltas() async {
        let recorder = RuntimeEventBatchRecorder()
        let bridge = RuntimeEventDispatchBridge { events in
            await recorder.record(events)
        }

        await bridge.enqueue(assistantDeltaEvent(delta: "Hel"))
        await bridge.enqueue(assistantDeltaEvent(delta: "lo"))
        await bridge.flushNow()

        let events = await recorder.allEvents()
        XCTAssertEqual(events.count, 1)
        guard case let .assistantMessageDelta(assistantDelta) = events[0] else {
            XCTFail("Expected assistant delta event.")
            return
        }

        XCTAssertEqual(assistantDelta.threadID, "thr")
        XCTAssertEqual(assistantDelta.turnID, "turn")
        XCTAssertEqual(assistantDelta.itemID, "item")
        XCTAssertEqual(assistantDelta.delta, "Hello")
        XCTAssertEqual(assistantDelta.channel, .finalResponse)
        XCTAssertNil(assistantDelta.stage)
    }

    func testAssistantDeltasDoNotCoalesceAcrossActionBoundary() async {
        let recorder = RuntimeEventBatchRecorder()
        let bridge = RuntimeEventDispatchBridge { events in
            await recorder.record(events)
        }

        await bridge.enqueue(assistantDeltaEvent(delta: "A"))
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
        await bridge.enqueue(assistantDeltaEvent(delta: "B"))
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

    func testAssistantDeltasDoNotCoalesceAcrossChannelBoundary() async {
        let recorder = RuntimeEventBatchRecorder()
        let bridge = RuntimeEventDispatchBridge { events in
            await recorder.record(events)
        }

        await bridge.enqueue(
            assistantDeltaEvent(
                delta: "Planning",
                channel: .progress
            )
        )
        await bridge.enqueue(
            assistantDeltaEvent(
                delta: "Answer",
                channel: .finalResponse
            )
        )
        await bridge.flushNow()

        let events = await recorder.allEvents()
        XCTAssertEqual(events.count, 2)
    }

    private func assistantDeltaEvent(
        delta: String,
        channel: RuntimeAssistantMessageChannel = .finalResponse
    ) -> CodexRuntimeEvent {
        .assistantMessageDelta(
            RuntimeAssistantMessageDelta(
                itemID: "item",
                threadID: "thr",
                turnID: "turn",
                delta: delta,
                channel: channel
            )
        )
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
