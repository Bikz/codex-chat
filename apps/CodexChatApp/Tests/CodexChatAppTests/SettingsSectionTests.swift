@testable import CodexChatShared
import XCTest

final class SettingsSectionTests: XCTestCase {
    func testSettingsSectionOrderingIsStable() {
        XCTAssertEqual(
            SettingsSection.allCases,
            [
                .account,
                .runtime,
                .generalProject,
                .safetyDefaults,
                .experimental,
                .diagnostics,
                .storage,
            ]
        )
    }

    func testSettingsSectionIdentifiersAndTitlesAreStable() {
        XCTAssertEqual(
            SettingsSection.allCases.map(\.id),
            ["account", "runtime", "generalProject", "safetyDefaults", "experimental", "diagnostics", "storage"]
        )
        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            ["Account", "Runtime", "General Project", "Safety Defaults", "Experimental", "Diagnostics", "Storage"]
        )
    }

    func testDefaultSelectionIsAccount() {
        XCTAssertEqual(SettingsSection.defaultSelection, .account)
    }
}
