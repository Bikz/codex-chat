@testable import CodexChatApp
import CodexChatCore
import CodexKit
import XCTest

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

    func testMemoryAutoSummaryFormattingRespectsMode() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let threadID = UUID()
        let userText = "Remember that I prefer SwiftUI."
        let assistantText = """
        Sure.
        - Prefer SwiftUI for UI work
        - Keep docs private
        """

        let markdownSummariesOnly = MemoryAutoSummary.markdown(
            timestamp: timestamp,
            threadID: threadID,
            userText: userText,
            assistantText: assistantText,
            actions: [
                ActionCard(threadID: threadID, method: "tool/run", title: "Ran command", detail: "echo hello"),
            ],
            mode: .summariesOnly
        )
        XCTAssertFalse(markdownSummariesOnly.contains("Key facts"))

        let markdownWithFacts = MemoryAutoSummary.markdown(
            timestamp: timestamp,
            threadID: threadID,
            userText: userText,
            assistantText: assistantText,
            actions: [],
            mode: .summariesAndKeyFacts
        )
        XCTAssertTrue(markdownWithFacts.contains("Key facts"))
        XCTAssertTrue(markdownWithFacts.contains("Prefer SwiftUI"))
    }

    func testModEditSafetyAbsolutePathResolvesRelativePathsWithinProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-mod-safety-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = ModEditSafety.absolutePath(for: "mods/LocalMod/ui.mod.json", projectPath: root.path)
        let expected = root
            .appendingPathComponent("mods/LocalMod/ui.mod.json")
            .standardizedFileURL
            .path
        XCTAssertEqual(resolved, expected)
    }

    func testModEditSafetyIsWithinDoesNotMatchSiblingRoots() {
        XCTAssertTrue(ModEditSafety.isWithin(rootPath: "/tmp/mods", path: "/tmp/mods/file.txt"))
        XCTAssertFalse(ModEditSafety.isWithin(rootPath: "/tmp/mods", path: "/tmp/mods2/file.txt"))
        XCTAssertTrue(ModEditSafety.isWithin(rootPath: "/tmp/mods/", path: "/tmp/mods/file.txt"))
    }

    func testModEditSafetyFilterModChangesSelectsGlobalAndProjectModFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-mod-safety-filter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let globalRoot = root.appendingPathComponent("globalMods", isDirectory: true)
        let projectRoot = root.appendingPathComponent("project", isDirectory: true)
        let projectMods = projectRoot.appendingPathComponent("mods", isDirectory: true)

        try FileManager.default.createDirectory(at: globalRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectMods, withIntermediateDirectories: true)

        let changes: [RuntimeFileChange] = [
            RuntimeFileChange(path: "mods/LocalMod/ui.mod.json", kind: "modify", diff: "{}"),
            RuntimeFileChange(
                path: globalRoot.appendingPathComponent("GlobalMod/ui.mod.json").path,
                kind: "modify",
                diff: "{}"
            ),
            RuntimeFileChange(path: "README.md", kind: "modify", diff: "{}"),
        ]

        let filtered = ModEditSafety.filterModChanges(
            changes: changes,
            projectPath: projectRoot.path,
            globalRootPath: globalRoot.path,
            projectRootPath: projectMods.path
        )

        XCTAssertEqual(Set(filtered.map(\.path)), Set([changes[0].path, changes[1].path]))
    }

    func testModEditSafetyFilterModChangesRejectsTraversalOutsideProjectMods() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-mod-safety-traversal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectRoot = root.appendingPathComponent("project", isDirectory: true)
        let projectMods = projectRoot.appendingPathComponent("mods", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let changes: [RuntimeFileChange] = [
            RuntimeFileChange(path: "../mods/evil.json", kind: "modify", diff: "{}"),
        ]

        let filtered = ModEditSafety.filterModChanges(
            changes: changes,
            projectPath: projectRoot.path,
            globalRootPath: nil,
            projectRootPath: projectMods.path
        )

        XCTAssertTrue(filtered.isEmpty)
    }

    func testModEditSafetySnapshotCaptureAndRestoreRestoresOriginalContents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-mod-safety-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let globalRoot = root.appendingPathComponent("globalMods", isDirectory: true)
        let projectRoot = root.appendingPathComponent("project", isDirectory: true)
        let projectMods = projectRoot.appendingPathComponent("mods", isDirectory: true)
        let snapshotsRoot = root.appendingPathComponent("snapshots", isDirectory: true)

        try FileManager.default.createDirectory(at: globalRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectMods, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshotsRoot, withIntermediateDirectories: true)

        let globalFile = globalRoot.appendingPathComponent("GlobalMod/ui.mod.json")
        try FileManager.default.createDirectory(at: globalFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "global-v1".write(to: globalFile, atomically: true, encoding: .utf8)

        let projectFile = projectMods.appendingPathComponent("LocalMod/ui.mod.json")
        try FileManager.default.createDirectory(at: projectFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "project-v1".write(to: projectFile, atomically: true, encoding: .utf8)

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let threadID = UUID()
        let snapshot = try ModEditSafety.captureSnapshot(
            snapshotsRootURL: snapshotsRoot,
            globalRootPath: globalRoot.path,
            projectRootPath: projectMods.path,
            threadID: threadID,
            startedAt: startedAt
        )

        try "global-v2".write(to: globalFile, atomically: true, encoding: .utf8)
        try "project-v2".write(to: projectFile, atomically: true, encoding: .utf8)

        try ModEditSafety.restore(from: snapshot)

        XCTAssertEqual(try String(contentsOf: globalFile, encoding: .utf8), "global-v1")
        XCTAssertEqual(try String(contentsOf: projectFile, encoding: .utf8), "project-v1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.rootURL.path))
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
