@testable import CodexChatShared
import XCTest

final class RuntimePoolTests: XCTestCase {
    func testScopedIDRoundTripParsesWorkerAndRawID() throws {
        let scoped = RuntimePool.scope(id: "thr_123", workerID: RuntimePoolWorkerID(3))
        XCTAssertEqual(scoped, "w3|thr_123")

        let parsed = try XCTUnwrap(RuntimePool.parseScopedID(scoped))
        XCTAssertEqual(parsed.0, RuntimePoolWorkerID(3))
        XCTAssertEqual(parsed.1, "thr_123")
    }

    func testUnscopedIDFallsBackWhenInputIsNotScoped() {
        XCTAssertEqual(RuntimePool.unscopedID("turn_abc"), "turn_abc")
    }

    func testResolveRouteRejectsMalformedScopedThreadID() {
        XCTAssertThrowsError(try RuntimePool.resolveRoute(fromScopedThreadID: "not-scoped"))
    }

    func testResolveRouteFromPossiblyScopedThreadIDFallsBackToPrimaryWorkerForLegacyIDs() {
        let route = RuntimePool.resolveRoute(fromPossiblyScopedThreadID: "thr_legacy")
        XCTAssertEqual(route.workerID, RuntimePoolWorkerID(0))
        XCTAssertEqual(route.threadID, "thr_legacy")
    }

    func testConsistentWorkerIDIsDeterministicAndBounded() throws {
        let threadID = try XCTUnwrap(UUID(uuidString: "D4E2DE84-8428-4933-8D2E-E73E8205A3F7"))
        let first = RuntimePool.consistentWorkerID(for: threadID, workerCount: 6)
        let second = RuntimePool.consistentWorkerID(for: threadID, workerCount: 6)

        XCTAssertEqual(first, second)
        XCTAssertGreaterThanOrEqual(first.rawValue, 0)
        XCTAssertLessThan(first.rawValue, 6)
    }
}
