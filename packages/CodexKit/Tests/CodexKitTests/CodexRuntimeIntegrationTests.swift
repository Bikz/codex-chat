@testable import CodexKit
import Foundation
import XCTest

final class CodexRuntimeIntegrationTests: XCTestCase {
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

    private struct TurnOutcome: Sendable, Equatable {
        var delta: String
        var changes: [RuntimeFileChange]
    }

    private static func collectTurnOutcome(runtime: CodexRuntime) async throws -> TurnOutcome {
        let stream = await runtime.events()
        var delta = ""
        var changes: [RuntimeFileChange] = []

        for await event in stream {
            switch event {
            case let .approvalRequested(request):
                try await runtime.respondToApproval(requestID: request.id, decision: .approveOnce)
            case let .assistantMessageDelta(_, chunk):
                delta += chunk
            case let .fileChangesUpdated(update):
                changes = update.changes
            case .turnCompleted:
                return TurnOutcome(delta: delta, changes: changes)
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
