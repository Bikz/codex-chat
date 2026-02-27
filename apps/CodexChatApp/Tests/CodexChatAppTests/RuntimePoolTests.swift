@testable import CodexChatShared
import CodexKit
import Foundation
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

    func testSelectWorkerIDPrefersLowerLoadWorkerWhenHashedWorkerIsHot() throws {
        let threadID = try XCTUnwrap(UUID(uuidString: "D4E2DE84-8428-4933-8D2E-E73E8205A3F7"))
        let hashed = RuntimePool.consistentWorkerID(for: threadID, workerCount: 4)
        var loadByWorkerID: [RuntimePoolWorkerID: Int] = [
            RuntimePoolWorkerID(0): 1,
            RuntimePoolWorkerID(1): 1,
            RuntimePoolWorkerID(2): 1,
            RuntimePoolWorkerID(3): 1,
        ]
        loadByWorkerID[hashed] = 6

        let selected = RuntimePool.selectWorkerID(
            for: threadID,
            workerCount: 4,
            pinnedWorkerID: nil,
            unavailableWorkerIDs: [],
            workerLoadByID: loadByWorkerID
        )

        XCTAssertNotEqual(selected, hashed)
        XCTAssertEqual(loadByWorkerID[selected], 1)
    }

    func testSelectWorkerIDKeepsHashedWorkerWhenLoadSkewIsSmall() throws {
        let threadID = try XCTUnwrap(UUID(uuidString: "D4E2DE84-8428-4933-8D2E-E73E8205A3F7"))
        let hashed = RuntimePool.consistentWorkerID(for: threadID, workerCount: 4)
        var loadByWorkerID: [RuntimePoolWorkerID: Int] = [
            RuntimePoolWorkerID(0): 1,
            RuntimePoolWorkerID(1): 1,
            RuntimePoolWorkerID(2): 1,
            RuntimePoolWorkerID(3): 1,
        ]
        loadByWorkerID[hashed] = 2

        let selected = RuntimePool.selectWorkerID(
            for: threadID,
            workerCount: 4,
            pinnedWorkerID: nil,
            unavailableWorkerIDs: [],
            workerLoadByID: loadByWorkerID
        )

        XCTAssertEqual(selected, hashed)
    }

    func testStartTurnRejectsOutOfRangeScopedWorkerID() async throws {
        let runtime = CodexRuntime(executableResolver: { nil })
        let pool = RuntimePool(primaryRuntime: runtime, configuredWorkerCount: 4)

        do {
            _ = try await pool.startTurn(
                scopedThreadID: "w999|thr_1",
                text: "hello",
                safetyConfiguration: nil,
                skillInputs: [],
                inputItems: [],
                turnOptions: nil
            )
            XCTFail("Expected invalidResponse for out-of-range scoped worker ID")
        } catch let error as CodexRuntimeError {
            switch error {
            case let .invalidResponse(message):
                XCTAssertTrue(message.contains("Invalid scoped runtime worker id"))
            default:
                XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testWorkerRestartBackoffSecondsGrowsAndCapsAtEightSeconds() {
        XCTAssertEqual(RuntimePool.workerRestartBackoffSeconds(forFailureCount: 1), 1)
        XCTAssertEqual(RuntimePool.workerRestartBackoffSeconds(forFailureCount: 2), 2)
        XCTAssertEqual(RuntimePool.workerRestartBackoffSeconds(forFailureCount: 3), 4)
        XCTAssertEqual(RuntimePool.workerRestartBackoffSeconds(forFailureCount: 4), 8)
        XCTAssertEqual(RuntimePool.workerRestartBackoffSeconds(forFailureCount: 9), 8)
    }

    func testWorkerRestartAttemptsAreBoundedByConsecutiveFailureCount() {
        XCTAssertTrue(RuntimePool.shouldAttemptWorkerRestart(forFailureCount: 1))
        XCTAssertTrue(RuntimePool.shouldAttemptWorkerRestart(forFailureCount: 4))
        XCTAssertFalse(RuntimePool.shouldAttemptWorkerRestart(forFailureCount: 5))
    }

    func testConsecutiveWorkerFailureCountResetsAfterSuccessfulRecovery() {
        let failedOnce = RuntimePool.nextConsecutiveWorkerFailureCount(previousCount: 0, didRecover: false)
        XCTAssertEqual(failedOnce, 1)

        let failedTwice = RuntimePool.nextConsecutiveWorkerFailureCount(previousCount: failedOnce, didRecover: false)
        XCTAssertEqual(failedTwice, 2)

        let recovered = RuntimePool.nextConsecutiveWorkerFailureCount(previousCount: failedTwice, didRecover: true)
        XCTAssertEqual(recovered, 0)

        XCTAssertTrue(RuntimePool.shouldAttemptWorkerRestart(forFailureCount: max(1, recovered)))
    }

    func testSnapshotReportsQueuedTurnsWhenWorkerPermitsAreExhausted() async throws {
        let maxPerWorkerEnvKey = "CODEXCHAT_MAX_PARALLEL_TURNS_PER_WORKER"
        let previousMaxPerWorker = ProcessInfo.processInfo.environment[maxPerWorkerEnvKey]
        setenv(maxPerWorkerEnvKey, "1", 1)
        defer {
            if let previousMaxPerWorker {
                setenv(maxPerWorkerEnvKey, previousMaxPerWorker, 1)
            } else {
                unsetenv(maxPerWorkerEnvKey)
            }
        }

        let fixture = try Self.makeDelayedCompletionFixtureExecutable(completionDelayMS: 350)
        defer {
            try? FileManager.default.removeItem(at: fixture.rootURL)
        }

        let runtime = CodexRuntime(executableResolver: { fixture.executablePath })
        let pool = RuntimePool(primaryRuntime: runtime, configuredWorkerCount: 2)

        do {
            try await pool.start()

            let localThreadID = UUID()
            await pool.pin(localThreadID: localThreadID, runtimeThreadID: "w1|thr_seed")
            let scopedThreadID = try await pool.startThread(
                localThreadID: localThreadID,
                cwd: nil,
                safetyConfiguration: nil
            )

            let firstTurnTask = Task {
                try await pool.startTurn(
                    scopedThreadID: scopedThreadID,
                    text: "first",
                    safetyConfiguration: nil,
                    skillInputs: [],
                    inputItems: [],
                    turnOptions: nil
                )
            }
            _ = try await firstTurnTask.value

            let secondTurnTask = Task {
                try await pool.startTurn(
                    scopedThreadID: scopedThreadID,
                    text: "second",
                    safetyConfiguration: nil,
                    skillInputs: [],
                    inputItems: [],
                    turnOptions: nil
                )
            }

            try await eventually(timeoutSeconds: 2.0) {
                let snapshot = await pool.snapshot()
                guard let workerMetrics = snapshot.workers.first(where: { $0.workerID == RuntimePoolWorkerID(1) }) else {
                    return false
                }
                return workerMetrics.queueDepth >= 1
                    && snapshot.totalQueuedTurns >= 1
                    && workerMetrics.inFlightTurns >= 1
            }

            _ = try await secondTurnTask.value

            try await eventually(timeoutSeconds: 3.0) {
                let settled = await pool.snapshot()
                return settled.totalQueuedTurns == 0 && settled.totalInFlightTurns == 0
            }

            await pool.stop()
            await runtime.stop()
        } catch {
            await pool.stop()
            await runtime.stop()
            throw error
        }
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

    private static func makeDelayedCompletionFixtureExecutable(completionDelayMS: Int) throws -> FixtureExecutable {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runtimepool-queued-metrics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let scriptURL = rootURL.appendingPathComponent("fake-codex-runtimepool-queued")

        let script = """
        #!/usr/bin/env python3
        import json
        import sys
        import time

        def send(message):
            sys.stdout.write(json.dumps(message) + "\\n")
            sys.stdout.flush()

        initialized = False
        next_thread = 1
        next_turn = 1
        known_threads = set()
        completion_delay_seconds = \(completionDelayMS) / 1000.0

        args = sys.argv[1:]
        if len(args) != 1 or args[0] != "app-server":
            sys.stderr.write("usage: fake-codex-runtimepool-queued app-server\\n")
            raise SystemExit(2)

        for raw in sys.stdin:
            line = raw.strip()
            if not line:
                continue

            try:
                msg = json.loads(line)
            except Exception:
                continue

            msg_id = msg.get("id")
            method = msg.get("method")
            params = msg.get("params") or {}
            result = msg.get("result")
            error = msg.get("error")

            is_request = msg_id is not None and method is not None and result is None and error is None
            is_notification = msg_id is None and method is not None and result is None and error is None

            if is_notification:
                if method == "initialized":
                    initialized = True
                continue

            if not is_request:
                continue

            if method == "initialize":
                send({
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {"capabilities": {"followUpSuggestions": {"version": 1}}}
                })
                continue

            if not initialized:
                send({
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "error": {"code": -32002, "message": "not initialized", "data": None}
                })
                continue

            if method == "account/read":
                send({
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {"requiresOpenaiAuth": True, "account": {"type": "apikey"}}
                })
                continue

            if method == "thread/start":
                thread_id = f"thr_{next_thread}"
                next_thread += 1
                known_threads.add(thread_id)
                send({"jsonrpc": "2.0", "id": msg_id, "result": {"thread": {"id": thread_id}}})
                send({"jsonrpc": "2.0", "method": "thread/started", "params": {"thread": {"id": thread_id}}})
                continue

            if method == "turn/start":
                thread_id = params.get("threadId")
                if thread_id not in known_threads:
                    send({
                        "jsonrpc": "2.0",
                        "id": msg_id,
                        "error": {"code": -32010, "message": f"unknown threadId: {thread_id}", "data": None}
                    })
                    continue

                turn_id = f"turn_{next_turn}"
                next_turn += 1
                send({"jsonrpc": "2.0", "id": msg_id, "result": {"turn": {"id": turn_id}}})
                send({
                    "jsonrpc": "2.0",
                    "method": "turn/started",
                    "params": {"threadId": thread_id, "turn": {"id": turn_id}}
                })
                send({
                    "jsonrpc": "2.0",
                    "method": "item/agentMessage/delta",
                    "params": {
                        "threadId": thread_id,
                        "turnId": turn_id,
                        "itemId": f"msg_{turn_id}",
                        "delta": "token"
                    }
                })
                time.sleep(completion_delay_seconds)
                send({
                    "jsonrpc": "2.0",
                    "method": "turn/completed",
                    "params": {"threadId": thread_id, "turn": {"id": turn_id, "status": "completed"}}
                })
                continue

            send({
                "jsonrpc": "2.0",
                "id": msg_id,
                "error": {"code": -32601, "message": f"method not found: {method}", "data": None}
            })
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: scriptURL.path
        )

        return FixtureExecutable(
            rootURL: rootURL,
            executablePath: scriptURL.path
        )
    }
}

private struct FixtureExecutable {
    let rootURL: URL
    let executablePath: String
}
