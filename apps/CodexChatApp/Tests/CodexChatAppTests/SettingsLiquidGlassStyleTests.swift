@testable import CodexChatShared
import SwiftUI
import XCTest

@MainActor
final class SettingsLiquidGlassStyleTests: XCTestCase {
    func testSafeAreaExtensionEdgesRemainTopOnly() {
        XCTAssertEqual(SettingsLiquidGlassStyle.safeAreaExtensionEdges, .top)
    }

    func testSidebarContainerStyleKeepsShadowOnlyForSolidMode() {
        let glass = SettingsLiquidGlassStyle.sidebarContainerStyle(glassEnabled: true)
        let solid = SettingsLiquidGlassStyle.sidebarContainerStyle(glassEnabled: false)

        XCTAssertEqual(glass.strokeOpacity, 0.14, accuracy: 0.0001)
        XCTAssertEqual(glass.shadowRadius, 0, accuracy: 0.0001)

        XCTAssertEqual(solid.strokeOpacity, 0.08, accuracy: 0.0001)
        XCTAssertEqual(solid.shadowRadius, 6, accuracy: 0.0001)
    }

    func testSectionCardStylePreservesPrimaryVsSecondaryWeight() {
        let primary = SettingsLiquidGlassStyle.sectionCardStyle(emphasis: .primary, glassEnabled: true)
        let secondary = SettingsLiquidGlassStyle.sectionCardStyle(emphasis: .secondary, glassEnabled: true)

        XCTAssertGreaterThan(primary.strokeOpacity, secondary.strokeOpacity)
        XCTAssertEqual(primary.shadowRadius, 0, accuracy: 0.0001)
        XCTAssertEqual(secondary.shadowRadius, 0, accuracy: 0.0001)
    }

    func testSidebarSelectionStyleHidesSelectionTreatmentWhenNotSelected() {
        let selected = SettingsLiquidGlassStyle.sidebarSelectionStyle(isSelected: true, glassEnabled: true)
        let idle = SettingsLiquidGlassStyle.sidebarSelectionStyle(isSelected: false, glassEnabled: true)

        XCTAssertEqual(selected.fillOpacity, 0.12, accuracy: 0.0001)
        XCTAssertEqual(selected.strokeOpacity, 0.22, accuracy: 0.0001)
        XCTAssertEqual(selected.indicatorOpacity, 1, accuracy: 0.0001)

        XCTAssertEqual(idle.fillOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(idle.strokeOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(idle.indicatorOpacity, 0, accuracy: 0.0001)
    }

    func testSettingsWindowSizingContractsRemainStable() {
        XCTAssertEqual(SettingsView.minimumWindowSize.width, 940, accuracy: 0.0001)
        XCTAssertEqual(SettingsView.minimumWindowSize.height, 620, accuracy: 0.0001)
        XCTAssertEqual(SettingsView.detailMaxContentWidth, 980, accuracy: 0.0001)
        XCTAssertEqual(SettingsView.themePresetGridColumnCount, 5)
    }

    func testSettingsSectionSubtitlesArePresentForEachSection() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
