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

    func testIgnoresNonProcessFailures() {
        let error = SkillCatalogError.invalidSource("bad source")
        XCTAssertNil(AppModel.extensibilityProcessFailureDetails(from: error))
    }
}
