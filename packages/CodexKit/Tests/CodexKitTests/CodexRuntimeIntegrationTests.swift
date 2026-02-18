@testable import CodexKit
import Foundation
import XCTest

final class CodexRuntimeIntegrationTests: XCTestCase {
    func testReadAccountPrefersNameOverFullName() async throws {
        let fakeCodexPath = try Self.makeAccountFixtureExecutable(
            account: [
                "type": "chatgpt",
                "name": "Preferred Name",
                "fullName": "Fallback Name",
                "email": "preferred@example.com",
                "planType": "pro",
            ]
        )
        let runtime = CodexRuntime(executableResolver: { fakeCodexPath })
        defer { Task { await runtime.stop() } }

        let state = try await runtime.readAccount(refreshToken: true)
        XCTAssertEqual(state.account?.name, "Preferred Name")
        XCTAssertEqual(state.account?.email, "preferred@example.com")
        XCTAssertEqual(state.account?.planType, "pro")
    }

    func testReadAccountFallsBackToFullNameWhenNameMissing() async throws {
        let fakeCodexPath = try Self.makeAccountFixtureExecutable(
            account: [
                "type": "chatgpt",
                "fullName": "Full Name Only",
                "email": "full@example.com",
            ]
        )
        let runtime = CodexRuntime(executableResolver: { fakeCodexPath })
        defer { Task { await runtime.stop() } }

        let state = try await runtime.readAccount()
        XCTAssertEqual(state.account?.name, "Full Name Only")
        XCTAssertEqual(state.account?.email, "full@example.com")
    }

    func testLegacyFixtureReportsNoCapabilities() async throws {
        let fakeCodexPath = try Self.resolveFakeCodexPath()
        guard FileManager.default.isExecutableFile(atPath: fakeCodexPath) else {
            throw XCTSkip("fake-codex fixture is not executable at \(fakeCodexPath)")
        }

        let runtime = CodexRuntime(executableResolver: { fakeCodexPath })
        defer { Task { await runtime.stop() } }

        _ = try await runtime.startThread(cwd: FileManager.default.temporaryDirectory.path)
        let capabilities = await runtime.capabilities()
        XCTAssertEqual(capabilities, .none)
    }

    func testLifecycleWithFakeAppServerStreamsApprovalAndCompletion() async throws {
        let fakeCodexPath = try Self.resolveFakeCodexPath()
        guard FileManager.default.isExecutableFile(atPath: fakeCodexPath) else {
            throw XCTSkip("fake-codex fixture is not executable at \(fakeCodexPath)")
        }

        let runtime = CodexRuntime(executableResolver: { fakeCodexPath })
        defer { Task { await runtime.stop() } }

        let threadID = try await runtime.startThread(cwd: FileManager.default.temporaryDirectory.path)
        XCTAssertEqual(threadID, "thr_test")

        let turnID = try await runtime.startTurn(threadID: threadID, text: "Hello")
        XCTAssertEqual(turnID, "turn_test")

        let outcome = try await withTimeout(seconds: 2.0) {
            try await Self.collectTurnOutcome(runtime: runtime)
        }

        XCTAssertEqual(outcome.delta, "Hello from fake runtime.")
        XCTAssertTrue(outcome.changes.contains(where: { $0.path == "notes.txt" }))
    }

    func testRestartDoesNotEmitRuntimeTerminatedActionForIntentionalRestart() async throws {
        let fakeCodexPath = try Self.resolveFakeCodexPath()
        guard FileManager.default.isExecutableFile(atPath: fakeCodexPath) else {
            throw XCTSkip("fake-codex fixture is not executable at \(fakeCodexPath)")
        }

        let runtime = CodexRuntime(executableResolver: { fakeCodexPath })
        defer { Task { await runtime.stop() } }

        _ = try await runtime.startThread(cwd: FileManager.default.temporaryDirectory.path)
        try await runtime.restart()

        let threadID = try await runtime.startThread(cwd: FileManager.default.temporaryDirectory.path)
        _ = try await runtime.startTurn(threadID: threadID, text: "After restart")

        let outcome = try await withTimeout(seconds: 2.0) {
            try await Self.collectTurnOutcome(runtime: runtime)
        }

        XCTAssertFalse(outcome.actionMethods.contains("runtime/terminated"))
        XCTAssertEqual(outcome.delta, "Hello from fake runtime.")
    }

    func testCapabilitiesFixtureSupportsSteerAndSuggestions() async throws {
        let fakeCodexPath = try Self.resolveFakeCodexSteerPath()
        guard FileManager.default.isExecutableFile(atPath: fakeCodexPath) else {
            throw XCTSkip("fake-codex-steer fixture is not executable at \(fakeCodexPath)")
        }

        let runtime = CodexRuntime(executableResolver: { fakeCodexPath })
        defer { Task { await runtime.stop() } }

        let stream = await runtime.events()
        let threadID = try await runtime.startThread(cwd: FileManager.default.temporaryDirectory.path)
        let capabilities = await runtime.capabilities()
        XCTAssertTrue(capabilities.supportsTurnSteer)
        XCTAssertTrue(capabilities.supportsFollowUpSuggestions)

        let turnID = try await runtime.startTurn(threadID: threadID, text: "Start a long turn")
        try await runtime.steerTurn(threadID: threadID, text: "Steer now", turnID: turnID)

        let outcome = try await withTimeout(seconds: 2.0) {
            var sawSuggestions = false
            var delta = ""
            for await event in stream {
                switch event {
                case .followUpSuggestions:
                    sawSuggestions = true
                case let .assistantMessageDelta(_, chunk):
                    delta += chunk
                case .turnCompleted:
                    return (sawSuggestions, delta)
                default:
                    continue
                }
            }

            throw XCTestError(.failureWhileWaiting)
        }

        XCTAssertTrue(outcome.0)
        XCTAssertTrue(outcome.1.contains("Steered: Steer now"))
    }

    private static func resolveFakeCodexPath(filePath: String = #filePath) throws -> String {
        var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while url.path != "/" {
            let marker = url.appendingPathComponent("pnpm-workspace.yaml").path
            if fileManager.fileExists(atPath: marker) {
                return url.appendingPathComponent("tests/fixtures/fake-codex").path
            }
            url.deleteLastPathComponent()
        }

        throw XCTSkip("Unable to locate repo root from \(filePath)")
    }

    private static func resolveFakeCodexSteerPath(filePath: String = #filePath) throws -> String {
        var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while url.path != "/" {
            let marker = url.appendingPathComponent("pnpm-workspace.yaml").path
            if fileManager.fileExists(atPath: marker) {
                return url.appendingPathComponent("tests/fixtures/fake-codex-steer").path
            }
            url.deleteLastPathComponent()
        }

        throw XCTSkip("Unable to locate repo root from \(filePath)")
    }

    private static func makeAccountFixtureExecutable(account: [String: Any]) throws -> String {
        let accountData = try JSONSerialization.data(withJSONObject: account, options: [])
        guard let accountJSON = String(data: accountData, encoding: .utf8) else {
            throw XCTSkip("Unable to encode fake account payload")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-account-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let scriptURL = root.appendingPathComponent("fake-codex-account")

        let script = """
        #!/usr/bin/env python3
        import json
        import sys

        def send(msg):
            sys.stdout.write(json.dumps(msg) + "\\n")
            sys.stdout.flush()

        initialized = False

        args = sys.argv[1:]
        if len(args) != 1 or args[0] != "app-server":
            sys.stderr.write("usage: fake-codex-account app-server\\n")
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
            result = msg.get("result")
            error = msg.get("error")

            is_request = msg_id is not None and method is not None and result is None and error is None
            is_notification = msg_id is None and method is not None and result is None and error is None

            if is_notification and method == "initialized":
                initialized = True
                continue

            if not is_request:
                continue

            if method == "initialize":
                send({"jsonrpc": "2.0", "id": msg_id, "result": {}})
                continue

            if not initialized:
                send({"jsonrpc": "2.0", "id": msg_id, "error": {"code": -32002, "message": "not initialized", "data": None}})
                continue

            if method == "account/read":
                send({
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {
                        "requiresOpenaiAuth": True,
                        "account": \(accountJSON)
                    }
                })
                continue

            send({"jsonrpc": "2.0", "id": msg_id, "error": {"code": -32601, "message": f"method not found: {method}", "data": None}})
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL.path
    }

    private struct TurnOutcome: Sendable, Equatable {
        var delta: String
        var changes: [RuntimeFileChange]
        var actionMethods: [String]
    }

    private static func collectTurnOutcome(runtime: CodexRuntime) async throws -> TurnOutcome {
        let stream = await runtime.events()
        var delta = ""
        var changes: [RuntimeFileChange] = []
        var actionMethods: [String] = []

        for await event in stream {
            switch event {
            case let .approvalRequested(request):
                try await runtime.respondToApproval(requestID: request.id, decision: .approveOnce)
            case let .assistantMessageDelta(_, chunk):
                delta += chunk
            case let .fileChangesUpdated(update):
                changes = update.changes
            case let .action(action):
                actionMethods.append(action.method)
            case .turnCompleted:
                return TurnOutcome(delta: delta, changes: changes, actionMethods: actionMethods)
            default:
                continue
            }
        }

        throw XCTestError(.failureWhileWaiting)
    }

    private struct TimeoutError: Error {}

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
