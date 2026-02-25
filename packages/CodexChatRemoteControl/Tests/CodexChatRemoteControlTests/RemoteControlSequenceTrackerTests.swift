@testable import CodexChatRemoteControl
import XCTest

final class RemoteControlSequenceTrackerTests: XCTestCase {
    func testAcceptsFirstSequenceAndContiguousProgression() {
        var tracker = RemoteControlSequenceTracker()

        XCTAssertEqual(tracker.ingest(10), .accepted)
        XCTAssertEqual(tracker.ingest(11), .accepted)
        XCTAssertEqual(tracker.lastSeenSequence, 11)
    }

    func testFlagsGapWithoutAdvancingLastSeen() {
        var tracker = RemoteControlSequenceTracker(lastSeenSequence: 20)

        XCTAssertEqual(
            tracker.ingest(24),
            .gapDetected(expectedNext: 21, received: 24)
        )
        XCTAssertEqual(tracker.lastSeenSequence, 20)
    }

    func testFlagsStaleForOutOfOrderOrDuplicateSequences() {
        var tracker = RemoteControlSequenceTracker(lastSeenSequence: 100)

        XCTAssertEqual(tracker.ingest(99), .stale(expectedNext: 101))
        XCTAssertEqual(tracker.ingest(100), .stale(expectedNext: 101))
        XCTAssertEqual(tracker.lastSeenSequence, 100)
    }
}
