@testable import CodexChatShared
import CodexKit
import XCTest

@MainActor
final class RuntimeAutoRecoveryTests: XCTestCase {
    func testAutomaticRecoveryStopsAfterConfiguredAttempts() async throws {
        let envKey = "CODEXCHAT_RUNTIME_AUTO_RECOVERY_BACKOFF_SECONDS"
        let previousValue = ProcessInfo.processInfo.environment[envKey]
        setenv(envKey, "0,0", 1)
        defer {
            if let previousValue {
                setenv(envKey, previousValue, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let runtime = CodexRuntime(executableResolver: { nil })
        let model = AppModel(repositories: nil, runtime: runtime, bootError: nil)
        defer { model.prepareForTeardown() }

        model.handleRuntimeTermination(detail: "Simulated runtime crash")

        try await waitUntil(timeout: 2.0) {
            model.runtimeAutoRecoveryTask == nil
        }

        let scheduledAttempts = model.logs.filter { entry in
            entry.message.contains("Auto-restart scheduled")
        }
        XCTAssertEqual(scheduledAttempts.count, 2)
        XCTAssertEqual(model.runtimeStatus, .error)
        XCTAssertEqual(
            model.runtimeIssue?.message,
            "Runtime stopped and automatic recovery failed. Use Restart Runtime to retry."
        )
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw XCTestError(.failureWhileWaiting)
    }
}
