import CodexChatCore
@testable import CodexChatShared
import Foundation
import XCTest

final class CodexChatRuntimeReliabilityArtifactsTests: XCTestCase {
    func testReplayThreadSummarizesStatusesAndTurns() throws {
        let projectRoot = try makeTempProjectRoot(prefix: "replay-summary")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let threadID = UUID()
        let firstTurnID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000311"))
        let secondTurnID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000312"))

        _ = try ChatArchiveStore.finalizeCheckpoint(
            projectPath: projectRoot.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                turnID: firstTurnID,
                timestamp: Date(timeIntervalSince1970: 1_700_200_001),
                status: .completed,
                userText: "first",
                assistantText: "done",
                actions: []
            )
        )

        _ = try ChatArchiveStore.failCheckpoint(
            projectPath: projectRoot.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                turnID: secondTurnID,
                timestamp: Date(timeIntervalSince1970: 1_700_200_002),
                status: .failed,
                userText: "second",
                assistantText: "",
                actions: [
                    ActionCard(
                        threadID: threadID,
                        method: "approval/reset",
                        title: "Approval reset",
                        detail: "Runtime restarted",
                        createdAt: Date(timeIntervalSince1970: 1_700_200_002)
                    ),
                ]
            )
        )

        let summary = try CodexChatBootstrap.replayThread(
            projectPath: projectRoot.path,
            threadID: threadID,
            limit: 10
        )

        XCTAssertEqual(summary.turnCount, 2)
        XCTAssertEqual(summary.completedTurnCount, 1)
        XCTAssertEqual(summary.failedTurnCount, 1)
        XCTAssertEqual(summary.pendingTurnCount, 0)
        XCTAssertEqual(summary.turns.last?.actions.count, 1)
        XCTAssertEqual(summary.turns.last?.actions.first?.method, "approval/reset")
    }

    func testLedgerExportWritesDeterministicJSON() throws {
        let projectRoot = try makeTempProjectRoot(prefix: "ledger-export")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let threadID = UUID()
        let turnID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000411"))

        _ = try ChatArchiveStore.finalizeCheckpoint(
            projectPath: projectRoot.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                turnID: turnID,
                timestamp: Date(timeIntervalSince1970: 1_700_200_101),
                status: .completed,
                userText: "question",
                assistantText: "answer",
                actions: [
                    ActionCard(
                        threadID: threadID,
                        method: "item/completed",
                        title: "Completed commandExecution",
                        detail: "echo hello",
                        createdAt: Date(timeIntervalSince1970: 1_700_200_102)
                    ),
                ]
            )
        )

        let outputURL = projectRoot
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("thread-ledger.json", isDirectory: false)

        let exportSummary = try CodexChatBootstrap.exportThreadLedger(
            projectPath: projectRoot.path,
            threadID: threadID,
            limit: 10,
            outputURL: outputURL
        )

        XCTAssertEqual(exportSummary.outputPath, outputURL.path)
        XCTAssertEqual(exportSummary.entryCount, 3)
        XCTAssertEqual(exportSummary.sha256.count, 64)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let data = try Data(contentsOf: outputURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(CodexChatThreadLedgerDocument.self, from: data)

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.threadID, threadID)
        XCTAssertEqual(document.entries.count, 3)
        XCTAssertEqual(document.entries.last?.kind, "action_card")
    }

    func testRuntimePolicyValidationReportsErrors() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-policy-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let validURL = root.appendingPathComponent("valid-policy.json", isDirectory: false)
        let invalidURL = root.appendingPathComponent("invalid-policy.json", isDirectory: false)

        let validPolicy = """
        {
          "version": 1,
          "defaultApprovalPolicy": "on-request",
          "defaultSandboxMode": "workspace-write",
          "allowNetworkAccess": true,
          "allowWebSearch": true,
          "allowDangerFullAccess": false,
          "allowNeverApproval": false
        }
        """
        try validPolicy.write(to: validURL, atomically: true, encoding: .utf8)

        let invalidPolicy = """
        {
          "version": 1,
          "defaultApprovalPolicy": "never",
          "defaultSandboxMode": "danger-full-access",
          "allowNetworkAccess": true,
          "allowWebSearch": true,
          "allowDangerFullAccess": false,
          "allowNeverApproval": false
        }
        """
        try invalidPolicy.write(to: invalidURL, atomically: true, encoding: .utf8)

        let validReport = try CodexChatBootstrap.validateRuntimePolicyDocument(at: validURL)
        XCTAssertTrue(validReport.isValid)
        XCTAssertTrue(validReport.issues.isEmpty)

        let invalidReport = try CodexChatBootstrap.validateRuntimePolicyDocument(at: invalidURL)
        XCTAssertFalse(invalidReport.isValid)
        XCTAssertTrue(invalidReport.issues.contains(where: { $0.message.contains("defaultApprovalPolicy=never") }))
        XCTAssertTrue(invalidReport.issues.contains(where: { $0.message.contains("defaultSandboxMode=danger-full-access") }))
    }

    func testLedgerBackfillIsIdempotentAndSupportsForce() throws {
        let projectRoot = try makeTempProjectRoot(prefix: "ledger-backfill")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let firstThreadID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000511"))
        let secondThreadID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000512"))
        let firstTurnID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000611"))
        let secondTurnID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000612"))

        _ = try ChatArchiveStore.finalizeCheckpoint(
            projectPath: projectRoot.path,
            threadID: firstThreadID,
            turn: ArchivedTurnSummary(
                turnID: firstTurnID,
                timestamp: Date(timeIntervalSince1970: 1_700_300_001),
                status: .completed,
                userText: "thread a",
                assistantText: "done",
                actions: []
            )
        )

        _ = try ChatArchiveStore.finalizeCheckpoint(
            projectPath: projectRoot.path,
            threadID: secondThreadID,
            turn: ArchivedTurnSummary(
                turnID: secondTurnID,
                timestamp: Date(timeIntervalSince1970: 1_700_300_002),
                status: .completed,
                userText: "thread b",
                assistantText: "done",
                actions: []
            )
        )

        let noiseFile = projectRoot
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)
            .appendingPathComponent("not-a-thread.md", isDirectory: false)
        try "noise".write(to: noiseFile, atomically: true, encoding: .utf8)

        let initialBackfill = try CodexChatBootstrap.backfillThreadLedgers(projectPath: projectRoot.path, limit: 10)
        XCTAssertEqual(initialBackfill.scannedThreadCount, 2)
        XCTAssertEqual(initialBackfill.exportedThreadCount, 2)
        XCTAssertEqual(initialBackfill.skippedThreadCount, 0)
        XCTAssertTrue(initialBackfill.threads.allSatisfy { $0.status == "exported" })

        for thread in initialBackfill.threads {
            XCTAssertTrue(FileManager.default.fileExists(atPath: thread.ledgerPath))
            XCTAssertTrue(FileManager.default.fileExists(atPath: thread.markerPath))
        }

        let secondBackfill = try CodexChatBootstrap.backfillThreadLedgers(projectPath: projectRoot.path, limit: 10)
        XCTAssertEqual(secondBackfill.scannedThreadCount, 2)
        XCTAssertEqual(secondBackfill.exportedThreadCount, 0)
        XCTAssertEqual(secondBackfill.skippedThreadCount, 2)
        XCTAssertTrue(secondBackfill.threads.allSatisfy { $0.status == "skipped" })

        let forcedBackfill = try CodexChatBootstrap.backfillThreadLedgers(
            projectPath: projectRoot.path,
            limit: 10,
            force: true
        )
        XCTAssertEqual(forcedBackfill.scannedThreadCount, 2)
        XCTAssertEqual(forcedBackfill.exportedThreadCount, 2)
        XCTAssertEqual(forcedBackfill.skippedThreadCount, 0)
        XCTAssertTrue(forcedBackfill.threads.allSatisfy { $0.status == "exported" })
    }

    func testLedgerBackfillDefaultLimitExportsFullThreadHistory() throws {
        let projectRoot = try makeTempProjectRoot(prefix: "ledger-backfill-full-history")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let threadID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000711"))
        for index in 0 ..< 120 {
            _ = try ChatArchiveStore.finalizeCheckpoint(
                projectPath: projectRoot.path,
                threadID: threadID,
                turn: ArchivedTurnSummary(
                    turnID: UUID(),
                    timestamp: Date(timeIntervalSince1970: 1_700_400_000 + TimeInterval(index)),
                    status: .completed,
                    userText: "turn-\(index)",
                    assistantText: "done-\(index)",
                    actions: []
                )
            )
        }

        let backfill = try CodexChatBootstrap.backfillThreadLedgers(projectPath: projectRoot.path)
        XCTAssertEqual(backfill.scannedThreadCount, 1)
        XCTAssertEqual(backfill.exportedThreadCount, 1)
        XCTAssertEqual(backfill.skippedThreadCount, 0)
        XCTAssertEqual(backfill.threads.first?.entryCount, 240)
    }

    func testLedgerBackfillReexportsWhenMarkerIsStale() throws {
        let projectRoot = try makeTempProjectRoot(prefix: "ledger-backfill-stale-marker")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let threadID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000811"))
        _ = try ChatArchiveStore.finalizeCheckpoint(
            projectPath: projectRoot.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                turnID: UUID(),
                timestamp: Date(timeIntervalSince1970: 1_700_500_001),
                status: .completed,
                userText: "question",
                assistantText: "answer",
                actions: []
            )
        )

        let initialBackfill = try CodexChatBootstrap.backfillThreadLedgers(projectPath: projectRoot.path, limit: 10)
        XCTAssertEqual(initialBackfill.exportedThreadCount, 1)
        let ledgerPath = try XCTUnwrap(initialBackfill.threads.first?.ledgerPath)
        try FileManager.default.removeItem(atPath: ledgerPath)

        let secondBackfill = try CodexChatBootstrap.backfillThreadLedgers(projectPath: projectRoot.path, limit: 10)
        XCTAssertEqual(secondBackfill.exportedThreadCount, 1)
        XCTAssertEqual(secondBackfill.skippedThreadCount, 0)
        XCTAssertEqual(secondBackfill.threads.first?.status, "exported")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ledgerPath))
    }

    func testLedgerBackfillReexportsWhenRequestedLimitChanges() throws {
        let projectRoot = try makeTempProjectRoot(prefix: "ledger-backfill-limit-change")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let threadID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000911"))
        for index in 0 ..< 20 {
            _ = try ChatArchiveStore.finalizeCheckpoint(
                projectPath: projectRoot.path,
                threadID: threadID,
                turn: ArchivedTurnSummary(
                    turnID: UUID(),
                    timestamp: Date(timeIntervalSince1970: 1_700_600_000 + TimeInterval(index)),
                    status: .completed,
                    userText: "bounded-\(index)",
                    assistantText: "bounded-answer-\(index)",
                    actions: []
                )
            )
        }

        let boundedBackfill = try CodexChatBootstrap.backfillThreadLedgers(projectPath: projectRoot.path, limit: 5)
        XCTAssertEqual(boundedBackfill.exportedThreadCount, 1)
        XCTAssertEqual(boundedBackfill.skippedThreadCount, 0)
        XCTAssertEqual(boundedBackfill.threads.first?.entryCount, 10)

        let fullBackfill = try CodexChatBootstrap.backfillThreadLedgers(projectPath: projectRoot.path)
        XCTAssertEqual(fullBackfill.exportedThreadCount, 1)
        XCTAssertEqual(fullBackfill.skippedThreadCount, 0)
        XCTAssertEqual(fullBackfill.threads.first?.status, "exported")
        XCTAssertEqual(fullBackfill.threads.first?.entryCount, 40)

        let markerPath = try XCTUnwrap(fullBackfill.threads.first?.markerPath)
        let markerData = try Data(contentsOf: URL(fileURLWithPath: markerPath, isDirectory: false))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let marker = try decoder.decode(CodexChatLedgerBackfillMarker.self, from: markerData)
        XCTAssertEqual(marker.turnLimit, .max)
    }

    func testLedgerBackfillReexportsWhenLedgerDigestMismatchesMarker() throws {
        let projectRoot = try makeTempProjectRoot(prefix: "ledger-backfill-digest-mismatch")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let threadID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000A11"))
        _ = try ChatArchiveStore.finalizeCheckpoint(
            projectPath: projectRoot.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                turnID: UUID(),
                timestamp: Date(timeIntervalSince1970: 1_700_700_001),
                status: .completed,
                userText: "question",
                assistantText: "answer",
                actions: []
            )
        )

        let initialBackfill = try CodexChatBootstrap.backfillThreadLedgers(projectPath: projectRoot.path, limit: 10)
        XCTAssertEqual(initialBackfill.exportedThreadCount, 1)
        let ledgerPath = try XCTUnwrap(initialBackfill.threads.first?.ledgerPath)

        let corruptedLedger = """
        {
          "schemaVersion": 1,
          "generatedAt": "2026-02-24T00:00:00Z",
          "projectPath": "\(projectRoot.path)",
          "threadID": "\(threadID.uuidString)",
          "entries": []
        }
        """
        try corruptedLedger.write(to: URL(fileURLWithPath: ledgerPath, isDirectory: false), atomically: true, encoding: .utf8)

        let secondBackfill = try CodexChatBootstrap.backfillThreadLedgers(projectPath: projectRoot.path, limit: 10)
        XCTAssertEqual(secondBackfill.exportedThreadCount, 1)
        XCTAssertEqual(secondBackfill.skippedThreadCount, 0)
        XCTAssertEqual(secondBackfill.threads.first?.status, "exported")
        XCTAssertEqual(secondBackfill.threads.first?.entryCount, 2)
    }

    private func makeTempProjectRoot(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
