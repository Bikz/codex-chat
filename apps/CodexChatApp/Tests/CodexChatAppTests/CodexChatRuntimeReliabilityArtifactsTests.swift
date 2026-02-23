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

    private func makeTempProjectRoot(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
