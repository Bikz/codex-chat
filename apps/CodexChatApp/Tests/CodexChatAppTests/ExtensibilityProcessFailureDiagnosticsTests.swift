@testable import CodexChatShared
import CodexExtensions
import CodexMods
import CodexSkills
import XCTest

@MainActor
final class ExtensibilityProcessFailureDiagnosticsTests: XCTestCase {
    func testClassifiesSkillTimeoutFailures() {
        let error = SkillCatalogError.commandFailed(
            command: "git pull --ff-only",
            output: "Timed out after 100ms"
        )

        let details = AppModel.extensibilityProcessFailureDetails(from: error)

        XCTAssertEqual(details?.kind, .timeout)
        XCTAssertEqual(details?.command, "git pull --ff-only")
        XCTAssertEqual(details?.summary, "Timed out after 100ms")
    }

    func testClassifiesModOutputLimitFailures() {
        let error = ModInstallServiceError.commandFailed(
            command: "git clone --depth 1 https://example.test/mod",
            output: "stdout line\n[output truncated after 1024 bytes]"
        )

        let details = AppModel.extensibilityProcessFailureDetails(from: error)

        XCTAssertEqual(details?.kind, .truncatedOutput)
        XCTAssertEqual(details?.summary, "stdout line")
    }

    func testClassifiesLaunchFailures() {
        let error = SkillCatalogError.commandFailed(
            command: "npx skills add acme/mod",
            output: "Failed to launch process: No such file or directory"
        )

        let details = AppModel.extensibilityProcessFailureDetails(from: error)

        XCTAssertEqual(details?.kind, .launch)
    }

    func testClassifiesExtensionRunnerTimeoutFailures() {
        let error = ExtensionWorkerRunnerError.timedOut(750)
        let details = AppModel.extensibilityProcessFailureDetails(from: error)

        XCTAssertEqual(details?.kind, .timeout)
        XCTAssertEqual(details?.command, "extension-worker")
        XCTAssertEqual(details?.summary, "Timed out after 750ms.")
    }

    func testClassifiesLaunchdCommandFailures() {
        let error = LaunchdManagerError.commandFailed("launchctl bootstrap gui/501/foo failed (1): permission denied")
        let details = AppModel.extensibilityProcessFailureDetails(from: error)

        XCTAssertEqual(details?.kind, .command)
        XCTAssertEqual(details?.command, "launchctl")
        XCTAssertEqual(details?.summary, "launchctl bootstrap gui/501/foo failed (1): permission denied")
    }

    func testClassifiesMalformedExtensionOutputAsProtocolFailure() {
        let error = ExtensionWorkerRunnerError.malformedOutput("Missing JSON line output")
        let details = AppModel.extensibilityProcessFailureDetails(from: error)
        XCTAssertEqual(details?.kind, .protocolViolation)
    }

    func testIgnoresNonProcessFailures() {
        let error = SkillCatalogError.invalidSource("bad source")
        XCTAssertNil(AppModel.extensibilityProcessFailureDetails(from: error))
    }

    func testBuildsTimeoutRecoveryPlaybook() {
        let event = AppModel.ExtensibilityDiagnosticEvent(
            surface: "extensions",
            operation: "hook",
            kind: "timeout",
            command: "extension-worker",
            summary: "Timed out after 750ms."
        )

        let playbook = AppModel.extensibilityDiagnosticPlaybook(for: event)

        XCTAssertEqual(playbook.headline, "Retry with a narrower scope")
        XCTAssertEqual(
            playbook.primaryStep,
            "Re-run the action after reducing payload size or splitting the task."
        )
        XCTAssertNil(playbook.suggestedCommand)
        XCTAssertNil(playbook.shortcut)
    }

    func testBuildsLaunchdCommandRecoveryPlaybook() {
        let event = AppModel.ExtensibilityDiagnosticEvent(
            surface: "extensions",
            operation: "automation",
            kind: "command",
            command: "launchctl bootstrap gui/501/com.example.mod",
            summary: "launchctl failed"
        )

        let playbook = AppModel.extensibilityDiagnosticPlaybook(for: event)

        XCTAssertEqual(playbook.headline, "Recover background automation state")
        XCTAssertEqual(
            playbook.primaryStep,
            "Re-enable background automations and confirm launchd permissions in Settings."
        )
        XCTAssertEqual(
            playbook.suggestedCommand,
            "launchctl bootstrap gui/501/com.example.mod"
        )
        XCTAssertEqual(playbook.shortcut, .openAppSettings)
    }

    func testBuildsGitCommandRecoveryPlaybook() {
        let event = AppModel.ExtensibilityDiagnosticEvent(
            surface: "skills",
            operation: "install",
            kind: "command",
            command: "git clone --depth 1 https://example.test/skill",
            summary: "authentication failed"
        )

        let playbook = AppModel.extensibilityDiagnosticPlaybook(for: event)

        XCTAssertEqual(playbook.headline, "Validate install source and command access")
        XCTAssertEqual(
            playbook.primaryStep,
            "Verify repository/package source trust, credentials, and network reachability."
        )
        XCTAssertEqual(
            playbook.suggestedCommand,
            "git clone --depth 1 https://example.test/skill"
        )
        XCTAssertNil(playbook.shortcut)
    }

    func testRollupAutomationTimelineEventsMergesContiguousMatchingEntriesWithinWindow() {
        let now = Date()
        let newest = makeAutomationEvent(id: UUID(), timestamp: now, summary: "launchctl failed")
        let older = makeAutomationEvent(
            id: UUID(),
            timestamp: now.addingTimeInterval(-40),
            summary: "launchctl failed"
        )
        let distinct = makeAutomationEvent(
            id: UUID(),
            timestamp: now.addingTimeInterval(-70),
            summary: "scheduler timeout"
        )

        let rollups = AppModel.rollupAutomationTimelineEvents(
            [newest, older, distinct],
            collapseWindowSeconds: 180
        )

        XCTAssertEqual(rollups.count, 2)
        XCTAssertEqual(rollups[0].occurrenceCount, 2)
        XCTAssertEqual(rollups[0].latestEvent.id, newest.id)
        XCTAssertEqual(rollups[0].collapsedEvents.map(\.id), [newest.id, older.id])
        XCTAssertEqual(rollups[1].occurrenceCount, 1)
    }

    func testRollupAutomationTimelineEventsKeepsSameEntriesSeparateOutsideWindow() {
        let now = Date()
        let newest = makeAutomationEvent(id: UUID(), timestamp: now, summary: "launchctl failed")
        let stale = makeAutomationEvent(
            id: UUID(),
            timestamp: now.addingTimeInterval(-600),
            summary: "launchctl failed"
        )

        let rollups = AppModel.rollupAutomationTimelineEvents(
            [newest, stale],
            collapseWindowSeconds: 180
        )

        XCTAssertEqual(rollups.count, 2)
        XCTAssertEqual(rollups.map(\.occurrenceCount), [1, 1])
        XCTAssertEqual(rollups[0].collapsedEvents.count, 1)
        XCTAssertEqual(rollups[1].collapsedEvents.count, 1)
    }

    func testRollupAutomationTimelineEventsDoesNotMergeAcrossDifferentInterleavedFingerprint() {
        let now = Date()
        let first = makeAutomationEvent(id: UUID(), timestamp: now, summary: "launchctl failed")
        let middle = makeAutomationEvent(
            id: UUID(),
            timestamp: now.addingTimeInterval(-20),
            kind: "timeout",
            summary: "worker timed out"
        )
        let lastMatchingFirst = makeAutomationEvent(
            id: UUID(),
            timestamp: now.addingTimeInterval(-40),
            summary: "launchctl failed"
        )

        let rollups = AppModel.rollupAutomationTimelineEvents(
            [first, middle, lastMatchingFirst],
            collapseWindowSeconds: 180
        )

        XCTAssertEqual(rollups.count, 3)
        XCTAssertEqual(rollups[0].latestEvent.summary, "launchctl failed")
        XCTAssertEqual(rollups[2].latestEvent.summary, "launchctl failed")
        XCTAssertEqual(rollups[0].occurrenceCount, 1)
        XCTAssertEqual(rollups[2].occurrenceCount, 1)
        XCTAssertEqual(rollups[0].collapsedEvents.count, 1)
        XCTAssertEqual(rollups[2].collapsedEvents.count, 1)
    }

    private func makeAutomationEvent(
        id: UUID,
        timestamp: Date,
        kind: String = "command",
        summary: String
    ) -> AppModel.ExtensibilityDiagnosticEvent {
        AppModel.ExtensibilityDiagnosticEvent(
            id: id,
            timestamp: timestamp,
            surface: "extensions",
            operation: "automation",
            kind: kind,
            command: "launchctl bootstrap gui/501/com.example.mod",
            modID: "com.example.mod",
            projectID: UUID(uuidString: "B26CF4D8-CE13-447A-A7F2-96313C1E1B58"),
            threadID: UUID(uuidString: "2F7219F4-67ED-4CE5-A501-06D8FB9E67D8"),
            summary: summary
        )
    }
}
