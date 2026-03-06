@testable import CodexChatShared
import CodexExtensions
import Foundation
import XCTest

final class BackgroundAutomationReconciliationTests: XCTestCase {
    func testPruneBackgroundAutomationJobsRemovesOnlyStaleCodexChatPlists() throws {
        let rootURL = try makeTempDirectory(prefix: "background-automation-prune")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let launchdDirectory = rootURL.appendingPathComponent("launchd", isDirectory: true)
        try FileManager.default.createDirectory(at: launchdDirectory, withIntermediateDirectories: true)

        let keptPlistURL = launchdDirectory.appendingPathComponent("app.codexchat.keep.plist", isDirectory: false)
        let stalePlistURL = launchdDirectory.appendingPathComponent("app.codexchat.stale.plist", isDirectory: false)
        let keptPayloadURL = launchdDirectory.appendingPathComponent("app.codexchat.keep.payload.json", isDirectory: false)
        let stalePayloadURL = launchdDirectory.appendingPathComponent("app.codexchat.stale.payload.json", isDirectory: false)
        let foreignPlistURL = launchdDirectory.appendingPathComponent("com.example.foreign.plist", isDirectory: false)
        try Data().write(to: keptPlistURL, options: [.atomic])
        try Data().write(to: stalePlistURL, options: [.atomic])
        try Data().write(to: keptPayloadURL, options: [.atomic])
        try Data().write(to: stalePayloadURL, options: [.atomic])
        try Data().write(to: foreignPlistURL, options: [.atomic])

        let recorder = LaunchctlCommandRecorder()
        let launchdManager = LaunchdManager { arguments in
            recorder.calls.append(arguments)
            return ""
        }

        let removedLabels = try AppModel.pruneBackgroundAutomationJobs(
            keepingLabels: ["app.codexchat.keep"],
            launchdDirectory: launchdDirectory,
            uid: 501,
            launchdManager: launchdManager
        )

        XCTAssertEqual(removedLabels, ["app.codexchat.stale"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptPlistURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stalePlistURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptPayloadURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stalePayloadURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreignPlistURL.path))
        XCTAssertEqual(recorder.calls, [["bootout", "gui/501/app.codexchat.stale"]])
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class LaunchctlCommandRecorder: @unchecked Sendable {
    var calls: [[String]] = []
}
