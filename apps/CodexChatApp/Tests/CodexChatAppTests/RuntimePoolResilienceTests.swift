@testable import CodexChatShared
import CodexKit
import Foundation
import XCTest

final class RuntimePoolResilienceTests: XCTestCase {
    func testNonPrimaryWorkerTerminationReassignsPinsAndSuppressesTerminationAction() async throws {
        let fixture = try Self.makeCrashFixtureExecutable()
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
            let initialRoute = try XCTUnwrap(RuntimePool.parseScopedID(scopedThreadID))
            XCTAssertEqual(initialRoute.0, RuntimePoolWorkerID(1))

            let eventRecorder = RuntimePoolEventRecorder()
            let stream = await pool.events()
            let eventTask = Task {
                for await event in stream {
                    await eventRecorder.record(event)
                }
            }

            do {
                _ = try await pool.startTurn(
                    scopedThreadID: scopedThreadID,
                    text: "trigger non-primary crash",
                    safetyConfiguration: nil,
                    skillInputs: [],
                    inputItems: [],
                    turnOptions: nil
                )
                XCTFail("Expected non-primary worker turn to fail when fixture exits")
            } catch {
                // Expected: worker process exits and request fails with transport closure.
            }

            try await eventually(timeoutSeconds: 6.0) {
                let snapshot = await pool.snapshot()
                guard let workerOne = snapshot.workers.first(where: { $0.workerID == RuntimePoolWorkerID(1) }) else {
                    return false
                }
                return workerOne.failureCount >= 1
            }

            let remappedScopedThreadID = try await pool.startThread(
                localThreadID: localThreadID,
                cwd: nil,
                safetyConfiguration: nil
            )
            let remappedRoute = try XCTUnwrap(RuntimePool.parseScopedID(remappedScopedThreadID))
            XCTAssertEqual(remappedRoute.0, RuntimePoolWorkerID(0))

            // Give the event pump a short window before we assert suppression.
            try await Task.sleep(nanoseconds: 200_000_000)
            let actionMethods = await eventRecorder.actionMethods()
            XCTAssertFalse(actionMethods.contains("runtime/terminated"))

            eventTask.cancel()
            _ = await eventTask.result
            await pool.stop()
            await runtime.stop()
        } catch {
            await pool.stop()
            await runtime.stop()
            throw error
        }
    }

    func testNonPrimaryWorkerRecoversAfterCrashAndResumesPinnedRouting() async throws {
        let fixture = try Self.makeCrashOnceThenRecoverFixtureExecutable()
        defer {
            try? FileManager.default.removeItem(at: fixture.rootURL)
        }

        let runtime = CodexRuntime(executableResolver: { fixture.executablePath })
        let pool = RuntimePool(primaryRuntime: runtime, configuredWorkerCount: 2)
        do {
            try await pool.start()

            let eventRecorder = RuntimePoolEventRecorder()
            let stream = await pool.events()
            let eventTask = Task {
                for await event in stream {
                    await eventRecorder.record(event)
                }
            }

            let crashingThreadID = UUID()
            await pool.pin(localThreadID: crashingThreadID, runtimeThreadID: "w1|thr_seed")
            let crashingScopedThreadID = try await pool.startThread(
                localThreadID: crashingThreadID,
                cwd: nil,
                safetyConfiguration: nil
            )
            let crashingRoute = try XCTUnwrap(RuntimePool.parseScopedID(crashingScopedThreadID))
            XCTAssertEqual(crashingRoute.0, RuntimePoolWorkerID(1))

            do {
                _ = try await pool.startTurn(
                    scopedThreadID: crashingScopedThreadID,
                    text: "trigger one-time crash",
                    safetyConfiguration: nil,
                    skillInputs: [],
                    inputItems: [],
                    turnOptions: nil
                )
                XCTFail("Expected first non-primary turn to fail while worker crashes")
            } catch {
                // Expected: one crash before recovery.
            }

            try await eventually(timeoutSeconds: 8.0) {
                let snapshot = await pool.snapshot()
                guard let workerOne = snapshot.workers.first(where: { $0.workerID == RuntimePoolWorkerID(1) }) else {
                    return false
                }
                return workerOne.health == .healthy
                    && workerOne.restartCount >= 1
                    && workerOne.failureCount == 0
            }

            let recoveredThreadID = UUID()
            await pool.pin(localThreadID: recoveredThreadID, runtimeThreadID: "w1|thr_recovered")
            let recoveredScopedThreadID = try await pool.startThread(
                localThreadID: recoveredThreadID,
                cwd: nil,
                safetyConfiguration: nil
            )
            let recoveredRoute = try XCTUnwrap(RuntimePool.parseScopedID(recoveredScopedThreadID))
            XCTAssertEqual(recoveredRoute.0, RuntimePoolWorkerID(1))

            let recoveredScopedTurnID = try await pool.startTurn(
                scopedThreadID: recoveredScopedThreadID,
                text: "turn after worker recovery",
                safetyConfiguration: nil,
                skillInputs: [],
                inputItems: [],
                turnOptions: nil
            )
            let recoveredTurnRoute = try XCTUnwrap(RuntimePool.parseScopedID(recoveredScopedTurnID))
            XCTAssertEqual(recoveredTurnRoute.0, RuntimePoolWorkerID(1))

            try await eventually(timeoutSeconds: 4.0) {
                await eventRecorder.completedTurnIDs().contains(recoveredScopedTurnID)
            }

            eventTask.cancel()
            _ = await eventTask.result
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

    private static func makeCrashFixtureExecutable() throws -> FixtureExecutable {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runtimepool-resilience-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let scriptURL = rootURL.appendingPathComponent("fake-codex-runtimepool-resilience")

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
        crashed = False

        args = sys.argv[1:]
        if len(args) != 1 or args[0] != "app-server":
            sys.stderr.write("usage: fake-codex-runtimepool-resilience app-server\\n")
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
                send({"jsonrpc": "2.0", "id": msg_id, "result": {"capabilities": {}}})
                continue

            if not initialized:
                send({
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "error": {"code": -32002, "message": "not initialized", "data": None}
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

                if not crashed:
                    crashed = True
                    sys.exit(42)

                turn_id = f"turn_{next_turn}"
                next_turn += 1
                send({"jsonrpc": "2.0", "id": msg_id, "result": {"turn": {"id": turn_id}}})
                send({"jsonrpc": "2.0", "method": "turn/started", "params": {"threadId": thread_id, "turn": {"id": turn_id}}})
                send({"jsonrpc": "2.0", "method": "turn/completed", "params": {"threadId": thread_id, "turn": {"id": turn_id, "status": "completed"}}})
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

        return FixtureExecutable(rootURL: rootURL, executablePath: scriptURL.path)
    }

    private static func makeCrashOnceThenRecoverFixtureExecutable() throws -> FixtureExecutable {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runtimepool-resilience-recover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let scriptURL = rootURL.appendingPathComponent("fake-codex-runtimepool-resilience-recover")
        let markerURL = rootURL.appendingPathComponent("worker-crashed-once.marker")

        let script = """
        #!/usr/bin/env python3
        import json
        from pathlib import Path
        import sys

        def send(message):
            sys.stdout.write(json.dumps(message) + "\\n")
            sys.stdout.flush()

        initialized = False
        next_thread = 1
        next_turn = 1
        known_threads = set()
        crash_marker = Path("\(markerURL.path)")

        args = sys.argv[1:]
        if len(args) != 1 or args[0] != "app-server":
            sys.stderr.write("usage: fake-codex-runtimepool-resilience-recover app-server\\n")
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
                send({"jsonrpc": "2.0", "id": msg_id, "result": {"capabilities": {}}})
                continue

            if not initialized:
                send({
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "error": {"code": -32002, "message": "not initialized", "data": None}
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

                if not crash_marker.exists():
                    crash_marker.write_text("crashed once\\n", encoding="utf-8")
                    sys.exit(42)

                turn_id = f"turn_{next_turn}"
                next_turn += 1
                send({"jsonrpc": "2.0", "id": msg_id, "result": {"turn": {"id": turn_id}}})
                send({"jsonrpc": "2.0", "method": "turn/started", "params": {"threadId": thread_id, "turn": {"id": turn_id}}})
                send({"jsonrpc": "2.0", "method": "turn/completed", "params": {"threadId": thread_id, "turn": {"id": turn_id, "status": "completed"}}})
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

        return FixtureExecutable(rootURL: rootURL, executablePath: scriptURL.path)
    }
}

private struct FixtureExecutable {
    let rootURL: URL
    let executablePath: String
}

private actor RuntimePoolEventRecorder {
    private var actionMethodsSeen: [String] = []
    private var completedTurnIDsSeen: Set<String> = []

    func record(_ event: CodexRuntimeEvent) {
        switch event {
        case let .action(action):
            actionMethodsSeen.append(action.method)
        case let .turnCompleted(completion):
            if let turnID = completion.turnID {
                completedTurnIDsSeen.insert(turnID)
            }
        default:
            return
        }
    }

    func actionMethods() -> [String] {
        actionMethodsSeen
    }

    func completedTurnIDs() -> Set<String> {
        completedTurnIDsSeen
    }
}
