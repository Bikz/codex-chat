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
}
