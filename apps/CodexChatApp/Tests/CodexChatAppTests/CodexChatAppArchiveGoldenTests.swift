@testable import CodexChatApp
import CodexChatCore
import Foundation
import XCTest

final class CodexChatAppArchiveGoldenTests: XCTestCase {
    func testChatArchiveMarkdownMatchesGoldenFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-archive-golden-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let threadID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let turn = ArchivedTurnSummary(
            timestamp: timestamp,
            userText: "Please update the README.",
            assistantText: "Done. README updated.",
            actions: [
                ActionCard(
                    threadID: threadID,
                    method: "item/completed",
                    title: "Completed fileChange",
                    detail: "Updated README.md",
                    createdAt: timestamp
                ),
            ]
        )

        let archiveURL = try ChatArchiveStore.appendTurn(projectPath: root.path, threadID: threadID, turn: turn)
        let actual = try String(contentsOf: archiveURL, encoding: .utf8)
        guard let expectedURL = Bundle.module.url(forResource: "chat-archive-golden", withExtension: "md") else {
            XCTFail("Missing chat archive golden fixture")
            return
        }
        let expected = try String(contentsOf: expectedURL, encoding: .utf8)

        XCTAssertEqual(actual, expected)
    }
}
