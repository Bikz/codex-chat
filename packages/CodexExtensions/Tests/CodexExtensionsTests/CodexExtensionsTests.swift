@testable import CodexExtensions
import Foundation
import XCTest

final class CodexExtensionsTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexExtensionsPackage.version, "0.1.0")
    }

    func testCronScheduleParsesAndFindsNextRun() throws {
        let schedule = try CronSchedule(expression: "0 9 * * 1-5")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 20, hour: 8, minute: 30))) // Friday

        let next = try XCTUnwrap(schedule.nextRun(after: start, timeZone: calendar.timeZone, calendar: calendar))
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 2)
        XCTAssertEqual(parts.day, 20)
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 0)
    }

    func testPermissionEvaluatorNeedsPromptThenAllows() {
        let requested: Set<ExtensionPermissionFlag> = [.projectRead, .projectWrite]
        let initial = ExtensionPermissionSnapshot(granted: [.projectRead], denied: [])

        let decision = ExtensionPermissionEvaluator.evaluate(requested: requested, snapshot: initial)
        guard case let .needsPrompt(missing) = decision else {
            return XCTFail("Expected prompt decision")
        }
        XCTAssertEqual(missing, [.projectWrite])

        let granted = ExtensionPermissionSnapshot(granted: requested, denied: [])
        let allowed = ExtensionPermissionEvaluator.evaluate(requested: requested, snapshot: granted)
        XCTAssertEqual(allowed, .allowed)
    }

    func testWorkerRunnerExecutesScriptAndParsesJSON() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let scriptURL = tempRoot.appendingPathComponent("worker.sh")
        let script = """
        #!/bin/zsh
        read line
        echo '{"ok":true,"inspector":{"title":"Summary","markdown":"One line"}}'
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let runner = ExtensionWorkerRunner()
        let hook = ExtensionHandlerDefinition(command: [scriptURL.path])
        let envelope = ExtensionEventEnvelope(
            event: .turnCompleted,
            timestamp: Date(),
            project: .init(id: UUID().uuidString, path: tempRoot.path),
            thread: .init(id: UUID().uuidString),
            turn: .init(id: UUID().uuidString, status: "completed"),
            payload: ["status": "completed"]
        )

        let result = try await runner.run(
            handler: hook,
            input: ExtensionWorkerInput(envelope: envelope),
            workingDirectory: tempRoot,
            timeoutMs: 5000
        )

        XCTAssertEqual(result.output.ok, true)
        XCTAssertEqual(result.output.inspector?.title, "Summary")
        XCTAssertEqual(result.output.inspector?.markdown, "One line")
    }

    func testWorkerRunnerResolvesNonAbsoluteCommandUsingEnv() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let runner = ExtensionWorkerRunner()
        let hook = ExtensionHandlerDefinition(command: [
            "sh",
            "-c",
            "read line; echo '{\"ok\":true,\"log\":\"via-path\"}'",
        ])
        let envelope = ExtensionEventEnvelope(
            event: .turnCompleted,
            timestamp: Date(),
            project: .init(id: UUID().uuidString, path: tempRoot.path),
            thread: .init(id: UUID().uuidString),
            turn: .init(id: UUID().uuidString, status: "completed"),
            payload: [:]
        )

        let result = try await runner.run(
            handler: hook,
            input: ExtensionWorkerInput(envelope: envelope),
            workingDirectory: tempRoot,
            timeoutMs: 5000
        )
        XCTAssertEqual(result.output.ok, true)
        XCTAssertEqual(result.output.log, "via-path")
    }
}
