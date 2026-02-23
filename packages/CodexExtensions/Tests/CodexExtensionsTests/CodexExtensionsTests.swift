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
        echo '{"ok":true,"modsBar":{"title":"Summary","markdown":"One line"}}'
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
        XCTAssertEqual(result.output.modsBar?.title, "Summary")
        XCTAssertEqual(result.output.modsBar?.markdown, "One line")
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

    func testWorkerRunnerParsesModsBarScopeAndActions() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let scriptURL = tempRoot.appendingPathComponent("worker-actions.sh")
        let script = """
        #!/bin/zsh
        read line
        printf "%s%s%s%s%s%s%s\\n" \
          '{"ok":true,"modsBar":{"title":"Prompt Book","markdown":"Saved prompts","scope":"global","actions":[' \
          '{"id":"send-1","label":"Ship Checklist","kind":"composer.insertAndSend","payload":{"text":"Run ship checklist."}},' \
          '{"id":"calendar","label":"Today","kind":"native.action","payload":{},' \
          '"nativeActionID":"calendar.today","safetyLevel":"read-only",' \
          '"requiresConfirmation":false,"externallyVisible":false}' \
          ']}}'
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
            payload: [:]
        )

        let result = try await runner.run(
            handler: hook,
            input: ExtensionWorkerInput(envelope: envelope),
            workingDirectory: tempRoot,
            timeoutMs: 5000
        )

        XCTAssertEqual(result.output.modsBar?.scope, .global)
        XCTAssertEqual(result.output.modsBar?.actions?.count, 2)
        XCTAssertEqual(result.output.modsBar?.actions?.first?.kind, .composerInsertAndSend)
        XCTAssertEqual(result.output.modsBar?.actions?.first?.payload["text"], "Run ship checklist.")

        let nativeAction = result.output.modsBar?.actions?.last
        XCTAssertEqual(nativeAction?.kind, .nativeAction)
        XCTAssertEqual(nativeAction?.nativeActionID, "calendar.today")
        XCTAssertEqual(nativeAction?.safetyLevel, .readOnly)
        XCTAssertEqual(nativeAction?.requiresConfirmation, false)
        XCTAssertEqual(nativeAction?.externallyVisible, false)
    }

    func testWorkerRunnerRejectsMalformedFirstOutputLine() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let scriptURL = tempRoot.appendingPathComponent("worker-malformed-first-line.sh")
        let script = """
        #!/bin/zsh
        read line
        echo "not-json"
        echo '{"ok":true}'
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
            payload: [:]
        )

        do {
            _ = try await runner.run(
                handler: hook,
                input: ExtensionWorkerInput(envelope: envelope),
                workingDirectory: tempRoot,
                timeoutMs: 5000
            )
            XCTFail("Expected malformed output error")
        } catch let error as ExtensionWorkerRunnerError {
            guard case .malformedOutput = error else {
                return XCTFail("Unexpected runner error: \(error)")
            }
        }
    }

    func testWorkerRunnerRejectsOutputOverConfiguredLimit() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let runner = ExtensionWorkerRunner()
        let hook = ExtensionHandlerDefinition(command: [
            "sh",
            "-c",
            "read line; echo '{\"ok\":true,\"log\":\"1234567890\"}'",
        ])
        let envelope = ExtensionEventEnvelope(
            event: .turnCompleted,
            timestamp: Date(),
            project: .init(id: UUID().uuidString, path: tempRoot.path),
            thread: .init(id: UUID().uuidString),
            turn: .init(id: UUID().uuidString, status: "completed"),
            payload: [:]
        )

        do {
            _ = try await runner.run(
                handler: hook,
                input: ExtensionWorkerInput(envelope: envelope),
                workingDirectory: tempRoot,
                timeoutMs: 5000,
                maxOutputBytes: 8
            )
            XCTFail("Expected output size error")
        } catch let error as ExtensionWorkerRunnerError {
            guard case let .outputTooLarge(maxBytes) = error else {
                return XCTFail("Unexpected runner error: \(error)")
            }
            XCTAssertEqual(maxBytes, 8)
        }
    }

    func testWorkerRunnerRejectsMalformedOutputFuzzSet() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let outputURL = tempRoot.appendingPathComponent("malformed-output.txt")
        let scriptURL = tempRoot.appendingPathComponent("worker-fuzz.sh")
        let script = """
        #!/bin/zsh
        read line
        cat "\(outputURL.path)"
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
            payload: [:]
        )

        for malformed in malformedOutputSamples(count: 24) {
            try "\(malformed)\n".write(to: outputURL, atomically: true, encoding: .utf8)
            do {
                _ = try await runner.run(
                    handler: hook,
                    input: ExtensionWorkerInput(envelope: envelope),
                    workingDirectory: tempRoot,
                    timeoutMs: 5000
                )
                XCTFail("Expected malformed output error for sample: \(malformed)")
            } catch let error as ExtensionWorkerRunnerError {
                guard case .malformedOutput = error else {
                    return XCTFail("Unexpected runner error: \(error)")
                }
            }
        }
    }

    func testExtensionStateStorePersistsThreadAndGlobalModsBarOutputs() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let store = ExtensionStateStore()
        let threadID = UUID()
        let projectID = UUID()

        let threadOutput = ExtensionModsBarOutput(
            title: "Thread Summary",
            markdown: "- completed",
            scope: .thread,
            actions: [
                .init(id: "clear", label: "Clear", kind: .emitEvent, payload: ["operation": "clear"]),
            ]
        )
        _ = try await store.writeModsBarOutput(
            output: threadOutput,
            modDirectory: tempRoot,
            threadID: threadID,
            projectID: nil
        )

        let projectOutput = ExtensionModsBarOutput(
            title: "Project Notes",
            markdown: "- project status",
            scope: .project,
            actions: [
                .init(id: "insert", label: "Insert", kind: .composerInsert, payload: ["text": "project note"]),
            ]
        )
        _ = try await store.writeModsBarOutput(
            output: projectOutput,
            modDirectory: tempRoot,
            threadID: nil,
            projectID: projectID
        )

        let globalOutput = ExtensionModsBarOutput(
            title: "Prompt Book",
            markdown: "- ship checklist",
            scope: .global,
            actions: [
                .init(id: "send", label: "Send", kind: .composerInsertAndSend, payload: ["text": "ship it"]),
            ]
        )
        _ = try await store.writeModsBarOutput(
            output: globalOutput,
            modDirectory: tempRoot,
            threadID: nil,
            projectID: nil
        )

        let loadedThread = try await store.readModsBarOutput(
            modDirectory: tempRoot,
            scope: .thread,
            threadID: threadID,
            projectID: nil
        )
        let loadedProject = try await store.readModsBarOutput(
            modDirectory: tempRoot,
            scope: .project,
            threadID: nil,
            projectID: projectID
        )
        let loadedGlobal = try await store.readModsBarOutput(
            modDirectory: tempRoot,
            scope: .global,
            threadID: nil,
            projectID: nil
        )

        XCTAssertEqual(loadedThread?.markdown, "- completed")
        XCTAssertEqual(loadedThread?.actions?.first?.id, "clear")
        XCTAssertEqual(loadedProject?.markdown, "- project status")
        XCTAssertEqual(loadedProject?.actions?.first?.id, "insert")
        XCTAssertEqual(loadedGlobal?.markdown, "- ship checklist")
        XCTAssertEqual(loadedGlobal?.actions?.first?.kind, .composerInsertAndSend)
    }

    private func malformedOutputSamples(count: Int) -> [String] {
        var samples: [String] = [
            "",
            "not-json",
            "{",
            "}",
            "[1,2",
            "\"unterminated",
            "{\"ok\":",
            "{\"modsBar\":",
        ]

        var state: UInt64 = 0xBAD5EED
        while samples.count < count {
            state = state &* 2_862_933_555_777_941_757 &+ 3_037_000_493
            let token = String(state, radix: 36)
            samples.append("malformed-\(token)")
        }

        return samples
    }
}
