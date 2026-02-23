import CodexExtensions
import CodexMods
import CodexSkills
@testable import CodexChatShared
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
    }
}
