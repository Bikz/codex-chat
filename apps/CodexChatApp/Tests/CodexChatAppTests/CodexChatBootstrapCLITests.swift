@testable import CodexChatShared
import Foundation
import XCTest

final class CodexChatBootstrapCLITests: XCTestCase {
    func testReproFixtureBasicTurnPasses() throws {
        let summary = try runFixture(named: "basic-turn")

        XCTAssertEqual(summary.fixtureName, "basic-turn")
        XCTAssertEqual(summary.actionCount, 1)
        XCTAssertEqual(summary.finalStatus, "completed")
    }

    func testReproFixtureRuntimeTerminationRecoveryPasses() throws {
        let summary = try runFixture(named: "runtime-termination-recovery")

        XCTAssertEqual(summary.fixtureName, "runtime-termination-recovery")
        XCTAssertEqual(summary.actionCount, 2)
        XCTAssertEqual(summary.finalStatus, "completed")
    }

    func testReproFixtureStaleThreadRemapPasses() throws {
        let summary = try runFixture(named: "stale-thread-remap")

        XCTAssertEqual(summary.fixtureName, "stale-thread-remap")
        XCTAssertEqual(summary.actionCount, 2)
        XCTAssertEqual(summary.finalStatus, "completed")
    }

    func testDoctorChecksIncludeCodexCLIEntry() {
        let checks = CodexChatBootstrap.doctorChecks(environment: ["PATH": "/usr/bin:/bin"])
        XCTAssertTrue(checks.contains(where: { $0.title == "Codex CLI" }))
    }

    private func runFixture(named fixtureName: String) throws -> CodexChatReproSummary {
        let fixturesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("repro", isDirectory: true)
        return try CodexChatBootstrap.runReproFixture(named: fixtureName, fixturesRoot: fixturesRoot)
    }
}
