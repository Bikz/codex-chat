@testable import CodexChatShared
import SwiftUI
import XCTest

@MainActor
final class DangerConfirmationSheetTests: XCTestCase {
    func testSubtitleCanBeCustomized() {
        let sheet = DangerConfirmationSheet(
            phrase: "ALLOW",
            subtitle: "Project-specific confirmation text.",
            input: .constant(""),
            errorText: nil,
            onCancel: {},
            onConfirm: {}
        )

        XCTAssertEqual(sheet.subtitle, "Project-specific confirmation text.")
    }

    func testPhraseMatchTrimsWhitespaceAndRequiresExactText() {
        XCTAssertTrue(DangerConfirmationSheet.isPhraseMatch(input: "  ALLOW  ", phrase: "ALLOW"))
        XCTAssertFalse(DangerConfirmationSheet.isPhraseMatch(input: "ALLOW NOW", phrase: "ALLOW"))
    }
}
