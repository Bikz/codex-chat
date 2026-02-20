@testable import CodexChatShared
import XCTest

final class AccountDisplayNamePreferenceTests: XCTestCase {
    func testNormalizedNameTrimsWhitespace() {
        XCTAssertEqual(
            AccountDisplayNamePreference.normalizedName("  Bikram Brar  "),
            "Bikram Brar"
        )
    }

    func testNormalizedNameReturnsNilForWhitespaceOnly() {
        XCTAssertNil(AccountDisplayNamePreference.normalizedName("   \n\t   "))
    }

    func testResolvedDisplayNamePrefersUserName() {
        XCTAssertEqual(
            AccountDisplayNamePreference.resolvedDisplayName(
                preferredName: "  Bikram Brar ",
                fallback: "bikram@example.com"
            ),
            "Bikram Brar"
        )
    }

    func testResolvedDisplayNameFallsBackWhenEmpty() {
        XCTAssertEqual(
            AccountDisplayNamePreference.resolvedDisplayName(
                preferredName: "   ",
                fallback: "API key login"
            ),
            "API key login"
        )
    }
}
