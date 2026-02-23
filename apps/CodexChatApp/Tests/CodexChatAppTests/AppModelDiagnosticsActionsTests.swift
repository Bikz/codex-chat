@testable import CodexChatShared
import XCTest

@MainActor
final class AppModelDiagnosticsActionsTests: XCTestCase {
    func testPrepareExtensibilityRerunCommandPopulatesComposer() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        model.prepareExtensibilityRerunCommand("git clone --depth 1 https://example.test/skill")

        XCTAssertTrue(model.composerText.contains("Troubleshoot and safely rerun this command"))
        XCTAssertTrue(model.composerText.contains("git clone --depth 1 https://example.test/skill"))
        XCTAssertEqual(
            model.followUpStatusMessage,
            "Prepared a safe rerun prompt in the composer. Review and send when ready."
        )
    }

    func testPrepareExtensibilityRerunCommandRejectsEmptyCommand() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        model.prepareExtensibilityRerunCommand("   ")

        XCTAssertEqual(
            model.followUpStatusMessage,
            "No rerun command is available for this diagnostics entry."
        )
        XCTAssertTrue(model.composerText.isEmpty)
    }

    func testAllowlistedExtensibilityRerunPolicyAllowsGitPull() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        XCTAssertTrue(model.isExtensibilityRerunCommandAllowlisted("git pull --ff-only"))
        XCTAssertEqual(
            model.extensibilityRerunCommandPolicyMessage("git pull --ff-only"),
            "Allowlisted direct rerun class: git."
        )
    }

    func testAllowlistedExtensibilityRerunPolicyBlocksShellChaining() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        XCTAssertFalse(model.isExtensibilityRerunCommandAllowlisted("git pull --ff-only && rm -rf /"))
        XCTAssertEqual(
            model.extensibilityRerunCommandPolicyMessage("git pull --ff-only && rm -rf /"),
            "Direct rerun blocked: Shell chaining or redirection operators are not allowed."
        )
    }

    func testExecuteAllowlistedRerunFallsBackToPreparedPromptWhenChatIsNotReady() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        model.executeAllowlistedExtensibilityRerunCommand("git pull --ff-only")

        XCTAssertTrue(model.composerText.contains("Troubleshoot and safely rerun this command"))
        XCTAssertTrue(model.composerText.contains("git pull --ff-only"))
        XCTAssertEqual(
            model.followUpStatusMessage,
            "Command is allowlisted, but chat is not ready. Review the prepared rerun prompt and send when ready."
        )
    }

    func testExecuteAllowlistedRerunRejectsBlockedCommand() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        model.executeAllowlistedExtensibilityRerunCommand("rm -rf /")

        XCTAssertTrue(model.composerText.isEmpty)
        XCTAssertEqual(
            model.followUpStatusMessage,
            "Direct rerun blocked: Command class is not allowlisted."
        )
    }

    func testFocusAutomationTimelineProjectSelectsProjectScope() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let projectID = UUID()

        model.focusAutomationTimelineProject(projectID)

        XCTAssertEqual(model.automationTimelineFocusFilter, .selectedProject)
    }

    func testFocusAutomationTimelineThreadSelectsThreadScope() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()

        model.focusAutomationTimelineThread(threadID)

        XCTAssertEqual(model.selectedThreadID, threadID)
        XCTAssertEqual(model.automationTimelineFocusFilter, .selectedThread)
    }
}
