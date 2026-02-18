import XCTest
@testable import CodexChatApp

final class CodexChatAppTests: XCTestCase {
    func testChatArchiveAppendAndRevealLookup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-archive-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let threadID = UUID()
        let summary = ArchivedTurnSummary(
            timestamp: Date(),
            userText: "Please update the README.",
            assistantText: "Done. README updated.",
            actions: []
        )

        let archiveURL = try ChatArchiveStore.appendTurn(
            projectPath: root.path,
            threadID: threadID,
            turn: summary
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        let content = try String(contentsOf: archiveURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Please update the README."))
        XCTAssertTrue(content.contains("Done. README updated."))

        let latest = ChatArchiveStore.latestArchiveURL(projectPath: root.path, threadID: threadID)
        XCTAssertEqual(
            latest?.resolvingSymlinksInPath().path,
            archiveURL.resolvingSymlinksInPath().path
        )
    }
}
