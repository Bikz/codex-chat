@testable import CodexChatShared
import CodexKit
import Foundation
import XCTest

final class RuntimePoolLoadHarnessTests: XCTestCase {
    private static let simulatedWorkerCount = 4
    private static let simulatedDeltaChunksPerTurn = 24
    private static let simulatedP95FirstTokenBudgetMS = 2500.0

    func testSimulatedRuntimePoolLoadHarnessScalesWithoutDropsOrMisroutes() async throws {
        let fixture = try Self.makeBurstFixtureExecutable(
            deltaChunksPerTurn: Self.simulatedDeltaChunksPerTurn
        )
        defer {
            try? FileManager.default.removeItem(at: fixture.rootURL)
        }

        for threadCount in [1, 5, 10, 25, 50] {
            let result = try await runSimulatedHarness(
                threadCount: threadCount,
                workerCount: Self.simulatedWorkerCount,
                executablePath: fixture.executablePath,
                expectedDeltaChunksPerTurn: Self.simulatedDeltaChunksPerTurn
            )

            XCTAssertEqual(
                result.droppedEventCount,
                0,
                "Dropped events under load \(threadCount): \(result.debugSummary)"
            )
            XCTAssertEqual(
                result.misroutedEventCount,
                0,
                "Misrouted events under load \(threadCount): \(result.debugSummary)"
            )
            XCTAssertLessThanOrEqual(
                result.p95FirstTokenMS,
                Self.simulatedP95FirstTokenBudgetMS,
                "p95 TTFT regression under load \(threadCount): \(result.debugSummary)"
            )
        }
    }

    func testRealRuntimeLoadSmokeWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CODEXCHAT_RUNTIME_LOAD_HARNESS_REAL"] == "1" else {
            throw XCTSkip("Set CODEXCHAT_RUNTIME_LOAD_HARNESS_REAL=1 to run real-runtime load smoke.")
        }

        guard let executablePath = CodexRuntime.defaultExecutableResolver() else {
            throw XCTSkip("Codex executable was not found on PATH.")
        }

        let result = try await runSimulatedHarness(
            threadCount: 5,
            workerCount: 1,
            executablePath: executablePath,
            expectedDeltaChunksPerTurn: 1
        )
        XCTAssertEqual(result.misroutedEventCount, 0, result.debugSummary)
    }

    private func runSimulatedHarness(
        threadCount: Int,
        workerCount: Int,
        executablePath: String,
        expectedDeltaChunksPerTurn: Int
    ) async throws -> RuntimePoolHarnessResult {
        let runtime = CodexRuntime(executableResolver: { executablePath })
        let runtimePool = RuntimePool(primaryRuntime: runtime, configuredWorkerCount: workerCount)

        do {
            try await runtimePool.start()
            let snapshot = await runtimePool.snapshot()
            XCTAssertEqual(snapshot.activeWorkerCount, workerCount)

            let localThreadIDs = (0 ..< threadCount).map { _ in UUID() }
            var scopedThreadIDByLocalThreadID: [UUID: String] = [:]
            for localThreadID in localThreadIDs {
                let scopedThreadID = try await runtimePool.startThread(
                    localThreadID: localThreadID,
                    cwd: nil,
                    safetyConfiguration: nil
                )
                scopedThreadIDByLocalThreadID[localThreadID] = scopedThreadID
            }

            let stream = await runtimePool.events()
            let collector = RuntimePoolHarnessCollector(
                expectedTurnCount: threadCount,
                expectedDeltaChunksPerTurn: expectedDeltaChunksPerTurn,
                localThreadIDByScopedThreadID: scopedThreadIDByLocalThreadID.reduce(into: [:]) {
                    $0[$1.value] = $1.key
                }
            )
            let clock = ContinuousClock()

            let eventTask = Task {
                for await event in stream {
                    await collector.record(event: event, receivedAt: clock.now)
                    if await collector.isTerminalStateReached {
                        break
                    }
                }
            }

            try await withThrowingTaskGroup(of: Void.self) { group in
                for localThreadID in localThreadIDs {
                    guard let scopedThreadID = scopedThreadIDByLocalThreadID[localThreadID] else {
                        continue
                    }

                    group.addTask {
                        await collector.recordDispatchStart(localThreadID: localThreadID, startedAt: clock.now)
                        let scopedTurnID = try await runtimePool.startTurn(
                            scopedThreadID: scopedThreadID,
                            text: "load-\(localThreadID.uuidString)",
                            safetyConfiguration: nil,
                            skillInputs: [],
                            inputItems: [],
                            turnOptions: nil
                        )
                        await collector.registerExpectedTurn(scopedTurnID: scopedTurnID, localThreadID: localThreadID)
                    }
                }

                try await group.waitForAll()
            }

            try await withTimeout(seconds: 20) {
                while await !(collector.isTerminalStateReached) {
                    try await Task.sleep(nanoseconds: 25_000_000)
                }
            }

            eventTask.cancel()
            _ = await eventTask.result

            let result = await collector.result()
            await runtimePool.stop()
            await runtime.stop()
            return result
        } catch {
            await runtimePool.stop()
            await runtime.stop()
            throw error
        }
    }

    private static func makeBurstFixtureExecutable(deltaChunksPerTurn: Int) throws -> FixtureExecutable {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-load-harness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let scriptURL = rootURL.appendingPathComponent("fake-codex-load")

        let script = """
        #!/usr/bin/env python3
        import json
        import sys

        def send(message):
            sys.stdout.write(json.dumps(message) + "\\n")
            sys.stdout.flush()

        initialized = False
        next_thread = 1
        next_turn = 1
        known_threads = set()
        delta_chunks_per_turn = \(deltaChunksPerTurn)

        args = sys.argv[1:]
        if len(args) != 1 or args[0] != "app-server":
            sys.stderr.write("usage: fake-codex-load app-server\\n")
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
                    "result": {
                        "capabilities": {
                            "followUpSuggestions": {"version": 1}
                        }
                    }
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

                item_id = f"msg_{turn_id}"
                for index in range(delta_chunks_per_turn):
                    send({
                        "jsonrpc": "2.0",
                        "method": "item/agentMessage/delta",
                        "params": {
                            "threadId": thread_id,
                            "turnId": turn_id,
                            "itemId": item_id,
                            "delta": f"{index:02d}|"
                        }
                    })

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

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            do {
                let value = try await group.next()!
                group.cancelAll()
                return value
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}

private struct FixtureExecutable {
    let rootURL: URL
    let executablePath: String
}

private struct RuntimePoolHarnessResult: Sendable {
    var droppedEventCount: Int
    var misroutedEventCount: Int
    var p95FirstTokenMS: Double
    var expectedTurnCount: Int
    var completedTurnCount: Int

    var debugSummary: String {
        "expectedTurns=\(expectedTurnCount), completedTurns=\(completedTurnCount), dropped=\(droppedEventCount), misrouted=\(misroutedEventCount), p95TTFT=\(String(format: "%.1f", p95FirstTokenMS))ms"
    }
}

private actor RuntimePoolHarnessCollector {
    private let expectedTurnCount: Int
    private let expectedDeltaChunksPerTurn: Int
    private let localThreadIDByScopedThreadID: [String: UUID]

    private var dispatchStartByLocalThreadID: [UUID: ContinuousClock.Instant] = [:]
    private var firstTokenAtByLocalThreadID: [UUID: ContinuousClock.Instant] = [:]
    private var expectedLocalThreadIDByScopedTurnID: [String: UUID] = [:]
    private var localThreadIDByScopedTurnID: [String: UUID] = [:]
    private var deltaCountByScopedTurnID: [String: Int] = [:]
    private var completedScopedTurnIDs: Set<String> = []
    private var misroutedEventCount: Int = 0

    init(
        expectedTurnCount: Int,
        expectedDeltaChunksPerTurn: Int,
        localThreadIDByScopedThreadID: [String: UUID]
    ) {
        self.expectedTurnCount = expectedTurnCount
        self.expectedDeltaChunksPerTurn = expectedDeltaChunksPerTurn
        self.localThreadIDByScopedThreadID = localThreadIDByScopedThreadID
    }

    var isTerminalStateReached: Bool {
        expectedLocalThreadIDByScopedTurnID.count == expectedTurnCount
            && completedScopedTurnIDs.count == expectedTurnCount
    }

    func recordDispatchStart(localThreadID: UUID, startedAt: ContinuousClock.Instant) {
        dispatchStartByLocalThreadID[localThreadID] = startedAt
    }

    func registerExpectedTurn(scopedTurnID: String, localThreadID: UUID) {
        expectedLocalThreadIDByScopedTurnID[scopedTurnID] = localThreadID
    }

    func record(event: CodexRuntimeEvent, receivedAt: ContinuousClock.Instant) {
        switch event {
        case let .turnStarted(scopedThreadID, scopedTurnID):
            guard let scopedThreadID else {
                misroutedEventCount += 1
                return
            }
            guard let localThreadID = localThreadIDByScopedThreadID[scopedThreadID] else {
                misroutedEventCount += 1
                return
            }

            if let routed = localThreadIDByScopedTurnID[scopedTurnID],
               routed != localThreadID
            {
                misroutedEventCount += 1
                return
            }
            localThreadIDByScopedTurnID[scopedTurnID] = localThreadID

        case let .assistantMessageDelta(scopedThreadID, scopedTurnID, _, _):
            guard let scopedThreadID, let scopedTurnID else {
                misroutedEventCount += 1
                return
            }
            guard let localThreadID = localThreadIDByScopedThreadID[scopedThreadID] else {
                misroutedEventCount += 1
                return
            }

            if let expectedLocal = expectedLocalThreadIDByScopedTurnID[scopedTurnID],
               expectedLocal != localThreadID
            {
                misroutedEventCount += 1
                return
            }

            if let routed = localThreadIDByScopedTurnID[scopedTurnID],
               routed != localThreadID
            {
                misroutedEventCount += 1
                return
            }

            localThreadIDByScopedTurnID[scopedTurnID] = localThreadID
            deltaCountByScopedTurnID[scopedTurnID, default: 0] += 1

            if firstTokenAtByLocalThreadID[localThreadID] == nil {
                firstTokenAtByLocalThreadID[localThreadID] = receivedAt
            }

        case let .turnCompleted(completion):
            guard let scopedThreadID = completion.threadID,
                  let scopedTurnID = completion.turnID,
                  let localThreadID = localThreadIDByScopedThreadID[scopedThreadID]
            else {
                misroutedEventCount += 1
                return
            }

            if let expectedLocal = expectedLocalThreadIDByScopedTurnID[scopedTurnID],
               expectedLocal != localThreadID
            {
                misroutedEventCount += 1
                return
            }

            if let routed = localThreadIDByScopedTurnID[scopedTurnID],
               routed != localThreadID
            {
                misroutedEventCount += 1
                return
            }

            completedScopedTurnIDs.insert(scopedTurnID)

        default:
            break
        }
    }

    func result() -> RuntimePoolHarnessResult {
        var missingChunkCount = 0
        for turnID in expectedLocalThreadIDByScopedTurnID.keys {
            let observed = deltaCountByScopedTurnID[turnID, default: 0]
            if observed < expectedDeltaChunksPerTurn {
                missingChunkCount += (expectedDeltaChunksPerTurn - observed)
            }
        }

        let missingCompletionCount = max(0, expectedTurnCount - completedScopedTurnIDs.count)
        let missingFirstTokenCount = max(0, expectedTurnCount - firstTokenAtByLocalThreadID.count)
        let droppedEventCount = missingChunkCount + missingCompletionCount + missingFirstTokenCount

        let p95FirstTokenMS = computeP95FirstTokenMS()
        return RuntimePoolHarnessResult(
            droppedEventCount: droppedEventCount,
            misroutedEventCount: misroutedEventCount,
            p95FirstTokenMS: p95FirstTokenMS,
            expectedTurnCount: expectedTurnCount,
            completedTurnCount: completedScopedTurnIDs.count
        )
    }

    private func computeP95FirstTokenMS() -> Double {
        var latenciesMS: [Double] = []
        latenciesMS.reserveCapacity(firstTokenAtByLocalThreadID.count)

        for (localThreadID, firstTokenAt) in firstTokenAtByLocalThreadID {
            guard let startedAt = dispatchStartByLocalThreadID[localThreadID] else {
                continue
            }
            let duration = startedAt.duration(to: firstTokenAt)
            let components = duration.components
            let milliseconds = (Double(components.seconds) * 1000)
                + (Double(components.attoseconds) / 1_000_000_000_000_000)
            latenciesMS.append(milliseconds)
        }

        guard !latenciesMS.isEmpty else {
            return .infinity
        }

        let sorted = latenciesMS.sorted()
        let clampedIndex = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
        return sorted[clampedIndex]
    }
}

private struct TimeoutError: Error {}
