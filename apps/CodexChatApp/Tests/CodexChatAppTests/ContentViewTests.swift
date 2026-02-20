@testable import CodexChatShared
import SwiftUI
import XCTest

@MainActor
final class ContentViewTests: XCTestCase {
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
