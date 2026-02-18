@testable import CodexChatShared
import Foundation
import XCTest

final class CodexChatBootstrapCLITests: XCTestCase {
    func testReproFixtureBasicTurnPasses() throws {
        let fixturesRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("repro", isDirectory: true)

        let summary = try CodexChatBootstrap.runReproFixture(named: "basic-turn", fixturesRoot: fixturesRoot)

        XCTAssertEqual(summary.fixtureName, "basic-turn")
        XCTAssertEqual(summary.actionCount, 1)
        XCTAssertEqual(summary.finalStatus, "completed")
    }

    func testDoctorChecksIncludeCodexCLIEntry() {
        let checks = CodexChatBootstrap.doctorChecks(environment: ["PATH": "/usr/bin:/bin"])
        XCTAssertTrue(checks.contains(where: { $0.title == "Codex CLI" }))
    }
}
