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
}
