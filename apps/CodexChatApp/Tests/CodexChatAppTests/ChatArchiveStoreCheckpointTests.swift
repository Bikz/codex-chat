import CodexChatCore
@testable import CodexChatShared
import Foundation
import XCTest

final class ChatArchiveStoreCheckpointTests: XCTestCase {
    func testBeginCheckpointWritesCanonicalThreadPath() throws {
        let root = try makeTempProjectRoot(prefix: "checkpoint-canonical")
        defer { try? FileManager.default.removeItem(at: root) }

        let threadID = UUID()
        let turnID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000101"))
        let timestamp = Date(timeIntervalSince1970: 1_700_100_000)

        let archiveURL = try ChatArchiveStore.beginCheckpoint(
            projectPath: root.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                turnID: turnID,
                timestamp: timestamp,
                userText: "Question",
                assistantText: "",
                actions: []
            )
        )

        let expected = root
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)
            .appendingPathComponent("\(threadID.uuidString).md", isDirectory: false)

        XCTAssertEqual(archiveURL.path, expected.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        let content = try String(contentsOf: archiveURL, encoding: .utf8)
        XCTAssertTrue(content.contains("status=pending"))
        XCTAssertTrue(content.contains("_Pending response..._"))
    }

    func testFinalizeCheckpointUpdatesExistingTurnAndPreservesActionDetails() throws {
        let root = try makeTempProjectRoot(prefix: "checkpoint-finalize")
        defer { try? FileManager.default.removeItem(at: root) }

        let threadID = UUID()
        let turnID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000102"))
        let timestamp = Date(timeIntervalSince1970: 1_700_100_100)

        _ = try ChatArchiveStore.beginCheckpoint(
            projectPath: root.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                turnID: turnID,
                timestamp: timestamp,
                userText: "Draft question",
                assistantText: "",
                actions: []
            )
        )

        let multilineDetail = "Line 1\nLine 2 \"quoted\""
        let finalizedURL = try ChatArchiveStore.finalizeCheckpoint(
            projectPath: root.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                turnID: turnID,
                timestamp: timestamp,
                userText: "Draft question",
                assistantText: "Final answer",
                actions: [
                    ActionCard(
                        threadID: threadID,
                        method: "item/completed",
                        title: "Completed fileChange",
                        detail: multilineDetail,
                        createdAt: timestamp
                    ),
                ]
            )
        )

        let content = try String(contentsOf: finalizedURL, encoding: .utf8)
        XCTAssertEqual(content.components(separatedBy: "<!-- CODEXCHAT_TURN_BEGIN id=\(turnID.uuidString)").count - 1, 1)
        XCTAssertTrue(content.contains("status=completed"))
        XCTAssertTrue(content.contains("Final answer"))
        XCTAssertTrue(content.contains("Line 1\\nLine 2 \\\"quoted\\\""))

        let turns = try ChatArchiveStore.loadRecentTurns(
            projectPath: root.path,
            threadID: threadID,
            limit: 10
        )
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.status, .completed)
        XCTAssertEqual(turns.first?.actions.first?.detail, multilineDetail)
    }

    func testFailCheckpointMarksTurnFailedAndKeepsUserText() throws {
        let root = try makeTempProjectRoot(prefix: "checkpoint-fail")
        defer { try? FileManager.default.removeItem(at: root) }

        let threadID = UUID()
        let turnID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000103"))
        let timestamp = Date(timeIntervalSince1970: 1_700_100_200)

        _ = try ChatArchiveStore.beginCheckpoint(
            projectPath: root.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                turnID: turnID,
                timestamp: timestamp,
                userText: "Will fail",
                assistantText: "",
                actions: []
            )
        )

        _ = try ChatArchiveStore.failCheckpoint(
            projectPath: root.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                turnID: turnID,
                timestamp: timestamp,
                userText: "Will fail",
                assistantText: "",
                actions: [
                    ActionCard(
                        threadID: threadID,
                        method: "turn/failure",
                        title: "Turn failed",
                        detail: "Runtime unavailable",
                        createdAt: timestamp
                    ),
                ]
            )
        )

        let turns = try ChatArchiveStore.loadRecentTurns(projectPath: root.path, threadID: threadID, limit: 10)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.status, .failed)
        XCTAssertEqual(turns.first?.userText, "Will fail")

        guard let archiveURL = ChatArchiveStore.latestArchiveURL(projectPath: root.path, threadID: threadID) else {
            XCTFail("Expected archive URL")
            return
        }

        let content = try String(contentsOf: archiveURL, encoding: .utf8)
        XCTAssertTrue(content.contains("status=failed"))
        XCTAssertTrue(content.contains("Will fail"))
        XCTAssertTrue(content.contains("_Turn failed before assistant output._"))
    }

    func testFinalizeCheckpointWriteFailurePreservesExistingArchiveContent() throws {
        let root = try makeTempProjectRoot(prefix: "checkpoint-write-failure")
        defer { try? FileManager.default.removeItem(at: root) }

        let threadID = UUID()
        let turnID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000104"))
        let timestamp = Date(timeIntervalSince1970: 1_700_100_300)

        let archiveURL = try ChatArchiveStore.beginCheckpoint(
            projectPath: root.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                turnID: turnID,
                timestamp: timestamp,
                userText: "Question before failure",
                assistantText: "",
                actions: []
            )
        )
        let before = try String(contentsOf: archiveURL, encoding: .utf8)

        let fileManager = FileManager.default
        let threadsDirectory = root
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)
        let originalPermissions = try fileManager.attributesOfItem(atPath: threadsDirectory.path)[.posixPermissions]
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o555)], ofItemAtPath: threadsDirectory.path)
        defer {
            if let originalPermissions {
                try? fileManager.setAttributes([.posixPermissions: originalPermissions], ofItemAtPath: threadsDirectory.path)
            } else {
                try? fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: threadsDirectory.path)
            }
        }

        XCTAssertThrowsError(
            try ChatArchiveStore.finalizeCheckpoint(
                projectPath: root.path,
                threadID: threadID,
                turn: ArchivedTurnSummary(
                    turnID: turnID,
                    timestamp: timestamp,
                    userText: "Question before failure",
                    assistantText: "This write should fail",
                    actions: []
                )
            )
        )

        let after = try String(contentsOf: archiveURL, encoding: .utf8)
        XCTAssertEqual(after, before)
        XCTAssertFalse(after.contains("This write should fail"))
    }

    func testLoadRecentTurnsReturnsOnlyLastFiftyTurns() throws {
        let root = try makeTempProjectRoot(prefix: "checkpoint-limit")
        defer { try? FileManager.default.removeItem(at: root) }

        let threadID = UUID()
        let base = Date(timeIntervalSince1970: 1_700_200_000)

        for offset in 0 ..< 55 {
            _ = try ChatArchiveStore.appendTurn(
                projectPath: root.path,
                threadID: threadID,
                turn: ArchivedTurnSummary(
                    turnID: UUID(),
                    timestamp: base.addingTimeInterval(TimeInterval(offset)),
                    userText: "Question \(offset)",
                    assistantText: "Answer \(offset)",
                    actions: []
                )
            )
        }

        let turns = try ChatArchiveStore.loadRecentTurns(projectPath: root.path, threadID: threadID, limit: 50)
        XCTAssertEqual(turns.count, 50)
        XCTAssertEqual(turns.first?.userText, "Question 5")
        XCTAssertEqual(turns.last?.assistantText, "Answer 54")
    }

    func testLegacyBackfillMergesDedupesAndWritesMarkerOnce() throws {
        let root = try makeTempProjectRoot(prefix: "checkpoint-backfill")
        defer { try? FileManager.default.removeItem(at: root) }

        let threadID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000111"))
        let chatsDir = root.appendingPathComponent("chats", isDirectory: true)
        let dayOne = chatsDir.appendingPathComponent("2026-01-01", isDirectory: true)
        let dayTwo = chatsDir.appendingPathComponent("2026-01-02", isDirectory: true)
        try FileManager.default.createDirectory(at: dayOne, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dayTwo, withIntermediateDirectories: true)

        let firstTurn = LegacyTurn(
            timestamp: "2026-01-01T00:00:00Z",
            user: "First",
            assistant: "One",
            actions: [LegacyAction(title: "Completed fileChange", method: "item/completed", detail: "notes.txt")]
        )
        let secondTurn = LegacyTurn(
            timestamp: "2026-01-01T00:01:00Z",
            user: "Second",
            assistant: "Two",
            actions: [LegacyAction(title: "Completed fileChange", method: "item/completed", detail: "todo.txt")]
        )

        let legacyOne = dayOne.appendingPathComponent("\(threadID.uuidString).md", isDirectory: false)
        let legacyTwo = dayTwo.appendingPathComponent("\(threadID.uuidString).md", isDirectory: false)

        try makeLegacyArchive(threadID: threadID, turns: [firstTurn]).write(to: legacyOne, atomically: true, encoding: .utf8)
        try makeLegacyArchive(threadID: threadID, turns: [firstTurn, secondTurn]).write(to: legacyTwo, atomically: true, encoding: .utf8)

        let inserted = try ChatArchiveStore.migrateLegacyDateShardedArchivesIfNeeded(projectPath: root.path)
        XCTAssertEqual(inserted, 2)

        let turns = try ChatArchiveStore.loadRecentTurns(projectPath: root.path, threadID: threadID, limit: Int.max)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns.map(\.userText), ["First", "Second"])

        let marker = chatsDir
            .appendingPathComponent("threads", isDirectory: true)
            .appendingPathComponent(".legacy-backfill-v1", isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))

        let rerun = try ChatArchiveStore.migrateLegacyDateShardedArchivesIfNeeded(projectPath: root.path)
        XCTAssertEqual(rerun, 0)

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyOne.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyTwo.path))
    }

    private struct LegacyAction {
        let title: String
        let method: String
        let detail: String
    }

    private struct LegacyTurn {
        let timestamp: String
        let user: String
        let assistant: String
        let actions: [LegacyAction]
    }

    private func makeLegacyArchive(threadID: UUID, turns: [LegacyTurn]) -> String {
        var content = "# Chat Archive for \(threadID.uuidString)\n\n"

        for turn in turns {
            content += "## Turn \(turn.timestamp)\n\n"
            content += "### User\n\n\(turn.user)\n\n"
            content += "### Assistant\n\n\(turn.assistant)\n\n"
            content += "### Actions\n\n"

            if turn.actions.isEmpty {
                content += "_None_\n\n"
            } else {
                for action in turn.actions {
                    content += "- **\(action.title)** (`\(action.method)`): \(action.detail)\n"
                }
                content += "\n"
            }

            content += "---\n\n"
        }

        return content
    }

    private func makeTempProjectRoot(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
