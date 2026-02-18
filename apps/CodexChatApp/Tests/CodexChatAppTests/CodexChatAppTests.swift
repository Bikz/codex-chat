import CodexKit
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

    func testApprovalStateMachineQueuesAndResolvesInOrder() {
        var state = ApprovalStateMachine()
        let first = makeApprovalRequest(id: 1)
        let second = makeApprovalRequest(id: 2)

        state.enqueue(first)
        state.enqueue(second)

        XCTAssertEqual(state.activeRequest?.id, 1)
        XCTAssertEqual(state.queuedRequests.map(\.id), [2])

        _ = state.resolve(id: 1)
        XCTAssertEqual(state.activeRequest?.id, 2)
        XCTAssertTrue(state.queuedRequests.isEmpty)

        _ = state.resolve(id: 2)
        XCTAssertNil(state.activeRequest)
        XCTAssertFalse(state.hasPendingApprovals)
    }

    func testApprovalStateMachineIgnoresDuplicateRequests() {
        var state = ApprovalStateMachine()
        let request = makeApprovalRequest(id: 42)

        state.enqueue(request)
        state.enqueue(request)

        XCTAssertEqual(state.activeRequest?.id, 42)
        XCTAssertTrue(state.queuedRequests.isEmpty)
    }

    private func makeApprovalRequest(id: Int) -> RuntimeApprovalRequest {
        RuntimeApprovalRequest(
            id: id,
            kind: .commandExecution,
            method: "item/commandExecution/requestApproval",
            threadID: "thr_1",
            turnID: "turn_1",
            itemID: "item_\(id)",
            reason: "test",
            risk: nil,
            cwd: "/tmp",
            command: ["echo", "hello"],
            changes: [],
            detail: "{}"
        )
    }
}
