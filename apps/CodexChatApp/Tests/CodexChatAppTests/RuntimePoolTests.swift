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
}
