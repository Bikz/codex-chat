@testable import CodexExtensions
import Foundation
import XCTest

final class FirstPartyModsScriptsTests: XCTestCase {
    func testPersonalNotesScriptSupportsAddEditAndClear() async throws {
        let modDirectory = try copyFirstPartyModFixture(relativePath: "mods/first-party/personal-notes")
        let threadID = UUID().uuidString

        let initial = try await runModScript(
            modDirectory: modDirectory,
            event: .threadStarted,
            threadID: threadID
        )
        XCTAssertEqual(initial.modsBar?.scope, .thread)
        XCTAssertTrue(initial.modsBar?.markdown.contains("No notes yet") == true)

        let upserted = try await runModScript(
            modDirectory: modDirectory,
            event: .modsBarAction,
            threadID: threadID,
            payload: [
                "operation": "upsert",
                "input": "Remember to run make quick before shipping.",
                "targetHookID": "notes-action",
            ]
        )
        XCTAssertEqual(upserted.modsBar?.markdown, "Remember to run make quick before shipping.")

        let cleared = try await runModScript(
            modDirectory: modDirectory,
            event: .modsBarAction,
            threadID: threadID,
            payload: [
                "operation": "clear",
                "targetHookID": "notes-action",
            ]
        )
        XCTAssertTrue(cleared.modsBar?.markdown.contains("No notes yet") == true)
    }

    func testThreadSummaryScriptAppendsAndClearsTimeline() async throws {
        let modDirectory = try copyFirstPartyModFixture(relativePath: "mods/first-party/thread-summary")
        let threadID = UUID().uuidString

        let completed = try await runModScript(
            modDirectory: modDirectory,
            event: .turnCompleted,
            threadID: threadID,
            payload: [
                "status": "completed",
            ]
        )
        XCTAssertTrue(completed.modsBar?.markdown.contains("completed") == true)

        let failed = try await runModScript(
            modDirectory: modDirectory,
            event: .turnFailed,
            threadID: threadID,
            payload: [
                "status": "failed",
                "error": "network timeout while calling provider",
            ]
        )
        XCTAssertTrue(failed.modsBar?.markdown.contains("failed") == true)
        XCTAssertTrue(failed.modsBar?.markdown.contains("network timeout") == true)

        let cleared = try await runModScript(
            modDirectory: modDirectory,
            event: .modsBarAction,
            threadID: threadID,
            payload: [
                "operation": "clear",
                "targetHookID": "summary-action",
            ]
        )
        XCTAssertEqual(cleared.modsBar?.markdown, "_No turns summarized yet._")
    }

    func testPromptBookScriptSupportsGlobalPersistenceAndFullActionSetAtMaxPrompts() async throws {
        let modDirectory = try copyFirstPartyModFixture(relativePath: "mods/first-party/prompt-book")
        let threadID = UUID().uuidString

        let initial = try await runModScript(
            modDirectory: modDirectory,
            event: .threadStarted,
            threadID: threadID
        )
        XCTAssertEqual(initial.modsBar?.scope, .global)
        XCTAssertEqual(initial.modsBar?.actions?.count, 7)

        var latest = initial
        for index in 0 ..< 10 {
            latest = try await runModScript(
                modDirectory: modDirectory,
                event: .modsBarAction,
                threadID: threadID,
                payload: [
                    "operation": "add",
                    "input": "Prompt \(index) :: Body \(index)",
                    "targetHookID": "prompt-book-action",
                ]
            )
        }

        XCTAssertEqual(latest.modsBar?.actions?.count, 37)
        XCTAssertEqual(latest.modsBar?.actions?.last?.id, "delete-11")

        let edited = try await runModScript(
            modDirectory: modDirectory,
            event: .modsBarAction,
            threadID: threadID,
            payload: [
                "operation": "edit",
                "index": "0",
                "input": "Ship Checklist :: Updated prompt body",
                "targetHookID": "prompt-book-action",
            ]
        )
        let sendZero = edited.modsBar?.actions?.first(where: { $0.id == "send-0" })
        XCTAssertEqual(sendZero?.payload["text"], "Updated prompt body")

        let deleted = try await runModScript(
            modDirectory: modDirectory,
            event: .modsBarAction,
            threadID: threadID,
            payload: [
                "operation": "delete",
                "index": "0",
                "targetHookID": "prompt-book-action",
            ]
        )
        XCTAssertEqual(deleted.modsBar?.actions?.count, 34)
        XCTAssertEqual(deleted.modsBar?.actions?.last?.id, "delete-10")
    }

    func testPersonalActionsPlaybookScriptProvidesExplicitComposerPlaybooks() async throws {
        let modDirectory = try copyFirstPartyModFixture(relativePath: "mods/first-party/personal-actions-playbook")
        let threadID = UUID().uuidString

        let output = try await runModScript(
            modDirectory: modDirectory,
            event: .threadStarted,
            threadID: threadID
        )

        XCTAssertEqual(output.modsBar?.scope, .thread)
        XCTAssertEqual(output.modsBar?.actions?.count, 3)
        XCTAssertTrue(output.modsBar?.markdown.contains("insert transparent prompts") == true)

        let actionIDs = Set(output.modsBar?.actions?.map(\.id) ?? [])
        XCTAssertEqual(
            actionIDs,
            Set([
                "playbook-message",
                "playbook-calendar",
                "playbook-desktop",
            ])
        )

        for action in output.modsBar?.actions ?? [] {
            XCTAssertEqual(action.kind, .composerInsert)
            XCTAssertFalse((action.payload["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        let actionsByID = Dictionary(uniqueKeysWithValues: (output.modsBar?.actions ?? []).map { ($0.id, $0) })
        XCTAssertTrue(actionsByID["playbook-message"]?.payload["text"]?.contains("$macos-send-message") == true)
        XCTAssertTrue(actionsByID["playbook-message"]?.payload["text"]?.contains("If intent is ambiguous") == true)
        XCTAssertTrue(actionsByID["playbook-calendar"]?.payload["text"]?.contains("$macos-calendar-assistant") == true)
        XCTAssertTrue(actionsByID["playbook-desktop"]?.payload["text"]?.contains("$macos-desktop-cleanup") == true)
    }

    private func runModScript(
        modDirectory: URL,
        event: ExtensionEventName,
        threadID: String,
        payload: [String: String] = [:]
    ) async throws -> ExtensionWorkerOutput {
        let runner = ExtensionWorkerRunner()
        let envelope = ExtensionEventEnvelope(
            event: event,
            timestamp: Date(),
            project: .init(id: UUID().uuidString, path: modDirectory.path),
            thread: .init(id: threadID),
            turn: nil,
            payload: payload
        )

        let result = try await runner.run(
            handler: .init(command: ["sh", scriptPath(for: modDirectory)], cwd: "."),
            input: ExtensionWorkerInput(envelope: envelope),
            workingDirectory: modDirectory,
            timeoutMs: 8000
        )
        return result.output
    }

    private func scriptPath(for modDirectory: URL) -> String {
        switch modDirectory.lastPathComponent {
        case "personal-notes":
            "scripts/notes.sh"
        case "thread-summary":
            "scripts/summary.sh"
        case "prompt-book":
            "scripts/prompt_book.sh"
        case "personal-actions-playbook":
            "scripts/personal_actions_playbook.sh"
        default:
            "scripts/hook.sh"
        }
    }

    private func copyFirstPartyModFixture(relativePath: String) throws -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(relativePath, isDirectory: true)
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-mod-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        let destinationURL = fixtureRoot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
}
