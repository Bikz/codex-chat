@testable import CodexChatShared
import XCTest

final class SettingsSectionTests: XCTestCase {
    func testSettingsSectionOrderingIsStable() {
        XCTAssertEqual(
            SettingsSection.allCases,
            [
                .account,
                .appearance,
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
            ["account", "appearance", "runtime", "generalProject", "safetyDefaults", "experimental", "diagnostics", "storage"]
        )
        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            ["Account", "Appearance", "Runtime", "General Project", "Safety Defaults", "Experimental", "Diagnostics", "Storage"]
        )
    }

    func testDefaultSelectionIsAccount() {
        XCTAssertEqual(SettingsSection.defaultSelection, .account)
    }
}
