@testable import CodexProcess
import XCTest

final class CodexProcessTests: XCTestCase {
    func testRunTimesOutWithConfiguredLimits() throws {
        XCTAssertThrowsError(
            try BoundedProcessRunner.run(
                ["sh", "-c", "sleep 1"],
                cwd: nil,
                limits: .init(timeoutMs: 100, maxOutputBytes: 131_072)
            )
        ) { error in
            guard case let BoundedProcessRunner.RunnerError.timedOut(timeoutMs, _, _) = error else {
                return XCTFail("Expected timedOut error, got \(error)")
            }
            XCTAssertEqual(timeoutMs, 100)
        }
    }

    func testRunTruncatesOutputWhenConfigured() throws {
        let result = try BoundedProcessRunner.run(
            ["perl", "-e", "print 'x' x 5000"],
            cwd: nil,
            limits: .init(timeoutMs: 120_000, maxOutputBytes: 1024)
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.output.count, 1024)
    }

    func testRunCheckedThrowsCommandErrorOnNonZeroExit() throws {
        XCTAssertThrowsError(
            try BoundedProcessRunner.runChecked(
                ["sh", "-c", "echo fail >&2; exit 9"],
                cwd: nil,
                limits: .init(timeoutMs: 1_000, maxOutputBytes: 16_384)
            )
        ) { error in
            guard case let BoundedProcessRunner.CommandError.failed(command, output) = error else {
                return XCTFail("Expected command error, got \(error)")
            }
            XCTAssertEqual(command, "sh -c echo fail >&2; exit 9")
            XCTAssertTrue(output.contains("fail"))
        }
    }

    func testRunCheckedIncludesTimeoutNotice() throws {
        XCTAssertThrowsError(
            try BoundedProcessRunner.runChecked(
                ["sh", "-c", "sleep 1"],
                cwd: nil,
                limits: .init(timeoutMs: 100, maxOutputBytes: 16_384)
            )
        ) { error in
            guard case let BoundedProcessRunner.CommandError.failed(_, output) = error else {
                return XCTFail("Expected command error, got \(error)")
            }
            XCTAssertTrue(output.contains("Timed out after 100ms"))
        }
    }
}
