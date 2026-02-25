@testable import CodexChatShared
import SwiftUI
import XCTest

@MainActor
final class ContentViewTests: XCTestCase {
    func testPrimaryToolbarSystemImagesWithoutModsBarMatchExpectedOrder() {
        XCTAssertEqual(
            ContentView.primaryToolbarSystemImages(canToggleModsBar: false),
            [
                ContentView.ToolbarIcon.pendingApprovals.rawValue,
                ContentView.ToolbarIcon.reviewChanges.rawValue,
                ContentView.ToolbarIcon.revealChatFile.rawValue,
                ContentView.ToolbarIcon.shellWorkspace.rawValue,
                ContentView.ToolbarIcon.planRunner.rawValue,
            ]
        )
    }

    func testPrimaryToolbarSystemImagesWithModsBarAppendsRightSidebarControl() {
        XCTAssertEqual(
            ContentView.primaryToolbarSystemImages(canToggleModsBar: true),
            [
                ContentView.ToolbarIcon.pendingApprovals.rawValue,
                ContentView.ToolbarIcon.reviewChanges.rawValue,
                ContentView.ToolbarIcon.revealChatFile.rawValue,
                ContentView.ToolbarIcon.shellWorkspace.rawValue,
                ContentView.ToolbarIcon.planRunner.rawValue,
                ContentView.ToolbarIcon.modsBar.rawValue,
            ]
        )
    }

    func testPrimaryToolbarSystemImagesDoNotContainSidebarLeftToggle() {
        XCTAssertFalse(
            ContentView.primaryToolbarSystemImages(canToggleModsBar: true).contains("sidebar.left")
        )
    }

    func testPrimaryToolbarSystemImagesRemainUnique() {
        let images = ContentView.primaryToolbarSystemImages(canToggleModsBar: true)
        XCTAssertEqual(Set(images).count, images.count)
    }

    func testCustomSidebarToolbarButtonRemainsDisabled() {
        XCTAssertFalse(ContentView.usesCustomSidebarToolbarButton)
    }

    func testSplitBackgroundExtensionRemainsTopEdgeOnly() {
        XCTAssertEqual(ContentView.splitBackgroundExtensionEdges, .top)
    }

    func testNextSplitViewVisibilityTogglesWhenNotOnboarding() {
        XCTAssertEqual(
            ContentView.nextSplitViewVisibility(current: .all, isOnboardingActive: false),
            .detailOnly
        )
        XCTAssertEqual(
            ContentView.nextSplitViewVisibility(current: .detailOnly, isOnboardingActive: false),
            .all
        )
    }

    func testNextSplitViewVisibilityForcesDetailOnlyDuringOnboarding() {
        XCTAssertEqual(
            ContentView.nextSplitViewVisibility(current: .all, isOnboardingActive: true),
            .detailOnly
        )
        XCTAssertEqual(
            ContentView.nextSplitViewVisibility(current: .detailOnly, isOnboardingActive: true),
            .detailOnly
        )
    }
}
