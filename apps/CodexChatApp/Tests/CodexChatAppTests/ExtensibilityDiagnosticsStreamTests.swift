@testable import CodexChatShared
import XCTest

@MainActor
final class ExtensibilityDiagnosticsStreamTests: XCTestCase {
    func testRecordExtensibilityDiagnosticStoresLatestEntry() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let details = AppModel.ExtensibilityProcessFailureDetails(
            kind: .timeout,
            command: "git pull --ff-only",
            summary: "Timed out after 100ms."
        )

        model.recordExtensibilityDiagnostic(
            surface: "skills",
            operation: "install",
            details: details
        )

        XCTAssertEqual(model.extensibilityDiagnostics.count, 1)
        XCTAssertEqual(model.extensibilityDiagnostics.first?.surface, "skills")
        XCTAssertEqual(model.extensibilityDiagnostics.first?.operation, "install")
        XCTAssertEqual(model.extensibilityDiagnostics.first?.kind, "timeout")
        XCTAssertEqual(model.extensibilityDiagnostics.first?.command, "git pull --ff-only")
    }

    func testRecordExtensibilityDiagnosticCapsHistory() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        for index in 0 ..< 105 {
            let details = AppModel.ExtensibilityProcessFailureDetails(
                kind: .command,
                command: "cmd-\(index)",
                summary: "summary-\(index)"
            )
            model.recordExtensibilityDiagnostic(
                surface: "mods",
                operation: "update",
                details: details
            )
        }

        XCTAssertEqual(model.extensibilityDiagnostics.count, 100)
        XCTAssertEqual(model.extensibilityDiagnostics.first?.summary, "summary-104")
        XCTAssertEqual(model.extensibilityDiagnostics.last?.summary, "summary-5")
    }
}
