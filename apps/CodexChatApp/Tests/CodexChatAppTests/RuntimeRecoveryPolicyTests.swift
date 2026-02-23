@testable import CodexChatShared
import XCTest

final class RuntimeRecoveryPolicyTests: XCTestCase {
    func testAppAutoRecoveryBackoffUsesFallbackWhenEnvironmentIsMissingOrInvalid() {
        XCTAssertEqual(
            RuntimeRecoveryPolicy.appAutoRecoveryBackoffSeconds(environmentValue: nil),
            RuntimeRecoveryPolicy.defaultAppAutoRecoveryBackoffSeconds
        )
        XCTAssertEqual(
            RuntimeRecoveryPolicy.appAutoRecoveryBackoffSeconds(environmentValue: "   "),
            RuntimeRecoveryPolicy.defaultAppAutoRecoveryBackoffSeconds
        )
        XCTAssertEqual(
            RuntimeRecoveryPolicy.appAutoRecoveryBackoffSeconds(environmentValue: "abc,def"),
            RuntimeRecoveryPolicy.defaultAppAutoRecoveryBackoffSeconds
        )
    }

    func testAppAutoRecoveryBackoffParsesAndCapsConfiguredValues() {
        XCTAssertEqual(
            RuntimeRecoveryPolicy.appAutoRecoveryBackoffSeconds(environmentValue: "0, 1, 2"),
            [0, 1, 2]
        )

        XCTAssertEqual(
            RuntimeRecoveryPolicy.appAutoRecoveryBackoffSeconds(
                environmentValue: "0,0,0,0,0,0,0,0,0",
                maxAttempts: 4
            ),
            [0, 0, 0, 0]
        )
    }

    func testWorkerRestartBackoffGrowsAndCaps() {
        XCTAssertEqual(RuntimeRecoveryPolicy.workerRestartBackoffSeconds(forConsecutiveFailureCount: 1), 1)
        XCTAssertEqual(RuntimeRecoveryPolicy.workerRestartBackoffSeconds(forConsecutiveFailureCount: 2), 2)
        XCTAssertEqual(RuntimeRecoveryPolicy.workerRestartBackoffSeconds(forConsecutiveFailureCount: 3), 4)
        XCTAssertEqual(RuntimeRecoveryPolicy.workerRestartBackoffSeconds(forConsecutiveFailureCount: 4), 8)
        XCTAssertEqual(RuntimeRecoveryPolicy.workerRestartBackoffSeconds(forConsecutiveFailureCount: 9), 8)
    }

    func testWorkerRestartAttemptsAreBoundedByConsecutiveFailures() {
        XCTAssertTrue(RuntimeRecoveryPolicy.shouldAttemptWorkerRestart(forConsecutiveFailureCount: 1, maxConsecutiveFailures: 4))
        XCTAssertTrue(RuntimeRecoveryPolicy.shouldAttemptWorkerRestart(forConsecutiveFailureCount: 4, maxConsecutiveFailures: 4))
        XCTAssertFalse(RuntimeRecoveryPolicy.shouldAttemptWorkerRestart(forConsecutiveFailureCount: 5, maxConsecutiveFailures: 4))
    }

    func testConsecutiveFailureCountResetsAfterRecovery() {
        let failedOnce = RuntimeRecoveryPolicy.nextConsecutiveWorkerFailureCount(previousCount: 0, didRecover: false)
        XCTAssertEqual(failedOnce, 1)

        let failedTwice = RuntimeRecoveryPolicy.nextConsecutiveWorkerFailureCount(previousCount: failedOnce, didRecover: false)
        XCTAssertEqual(failedTwice, 2)

        let recovered = RuntimeRecoveryPolicy.nextConsecutiveWorkerFailureCount(previousCount: failedTwice, didRecover: true)
        XCTAssertEqual(recovered, 0)
    }
}
