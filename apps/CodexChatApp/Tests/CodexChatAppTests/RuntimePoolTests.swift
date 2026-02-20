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

    func testResolveRouteRejectsMalformedScopedThreadID() {
        XCTAssertThrowsError(try RuntimePool.resolveRoute(fromScopedThreadID: "not-scoped"))
    }

    func testParseScopedIDRejectsNegativeWorkerID() {
        XCTAssertNil(RuntimePool.parseScopedID("w-1|thr_123"))
    }

    func testResolveScopedRuntimeIDRejectsMalformedID() {
        XCTAssertThrowsError(
            try RuntimePool.resolveScopedRuntimeID(
                "turn_legacy",
                expectedWorkerID: RuntimePoolWorkerID(0),
                kind: "turn"
            )
        )
    }

    func testResolveScopedRuntimeIDRejectsWrongWorker() {
        let scopedTurnID = RuntimePool.scope(id: "turn_123", workerID: RuntimePoolWorkerID(1))
        XCTAssertThrowsError(
            try RuntimePool.resolveScopedRuntimeID(
                scopedTurnID,
                expectedWorkerID: RuntimePoolWorkerID(2),
                kind: "turn"
            )
        )
    }

    func testConsistentWorkerIDIsDeterministicAndBounded() throws {
        let threadID = try XCTUnwrap(UUID(uuidString: "D4E2DE84-8428-4933-8D2E-E73E8205A3F7"))
        let first = RuntimePool.consistentWorkerID(for: threadID, workerCount: 6)
        let second = RuntimePool.consistentWorkerID(for: threadID, workerCount: 6)

        XCTAssertEqual(first, second)
        XCTAssertGreaterThanOrEqual(first.rawValue, 0)
        XCTAssertLessThan(first.rawValue, 6)
    }

    func testSelectWorkerIDHonorsAvailablePinnedWorker() throws {
        let threadID = try XCTUnwrap(UUID(uuidString: "A3194EB9-AE8F-46CE-8F74-78D721C06DC2"))
        let selected = RuntimePool.selectWorkerID(
            for: threadID,
            workerCount: 4,
            pinnedWorkerID: RuntimePoolWorkerID(2),
            unavailableWorkerIDs: []
        )
        XCTAssertEqual(selected, RuntimePoolWorkerID(2))
    }

    func testSelectWorkerIDFallsBackWhenPinnedWorkerUnavailable() throws {
        let threadID = try XCTUnwrap(UUID(uuidString: "A3194EB9-AE8F-46CE-8F74-78D721C06DC2"))
        let selected = RuntimePool.selectWorkerID(
            for: threadID,
            workerCount: 4,
            pinnedWorkerID: RuntimePoolWorkerID(2),
            unavailableWorkerIDs: [RuntimePoolWorkerID(2)]
        )
        XCTAssertNotEqual(selected, RuntimePoolWorkerID(2))
    }

    func testSelectWorkerIDAvoidsUnavailableHashedWorker() throws {
        let threadID = try XCTUnwrap(UUID(uuidString: "D4E2DE84-8428-4933-8D2E-E73E8205A3F7"))
        let hashed = RuntimePool.consistentWorkerID(for: threadID, workerCount: 4)
        let selected = RuntimePool.selectWorkerID(
            for: threadID,
            workerCount: 4,
            pinnedWorkerID: nil,
            unavailableWorkerIDs: [hashed]
        )

        XCTAssertNotEqual(selected, hashed)
        XCTAssertGreaterThanOrEqual(selected.rawValue, 0)
        XCTAssertLessThan(selected.rawValue, 4)
    }
}
