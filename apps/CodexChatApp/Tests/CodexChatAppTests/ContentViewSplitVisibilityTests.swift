@testable import CodexChatShared
import SwiftUI
import XCTest

@MainActor
final class ContentViewSplitVisibilityTests: XCTestCase {
    func testNextSplitViewVisibilityKeepsDetailOnlyDuringOnboarding() {
        XCTAssertEqual(
            ContentView.nextSplitViewVisibility(current: .all, isOnboardingActive: true),
            .detailOnly
        )
        XCTAssertEqual(
            ContentView.nextSplitViewVisibility(current: .detailOnly, isOnboardingActive: true),
            .detailOnly
        )
    }

    func testNextSplitViewVisibilityTogglesBetweenAllAndDetailOnly() {
        XCTAssertEqual(
            ContentView.nextSplitViewVisibility(current: .all, isOnboardingActive: false),
            .detailOnly
        )
        XCTAssertEqual(
            ContentView.nextSplitViewVisibility(current: .detailOnly, isOnboardingActive: false),
            .all
        )
    }
}
