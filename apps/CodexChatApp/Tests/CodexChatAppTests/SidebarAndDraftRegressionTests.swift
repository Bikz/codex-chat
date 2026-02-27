@testable import CodexChatShared
import XCTest

@MainActor
final class SidebarAndDraftRegressionTests: XCTestCase {
    func testSidebarProjectsPreviewStorageAndOptionsAreStable() {
        XCTAssertEqual(SidebarView.projectsPreviewCountStorageKey, "codexchat.sidebar.projectsPreviewCount")
        XCTAssertEqual(SidebarView.projectsPreviewCountOptions, [3, 5, 8, 12])
        XCTAssertEqual(SidebarView.threadFilterStorageKey, "codexchat.sidebar.threadFilter")
    }

    func testSettingsAppearanceUsesSidebarProjectsPreviewConfig() {
        XCTAssertEqual(SettingsView.sidebarProjectsPreviewStorageKey, SidebarView.projectsPreviewCountStorageKey)
        XCTAssertEqual(SettingsView.sidebarProjectsPreviewOptions, SidebarView.projectsPreviewCountOptions)
    }

    func testDraftEmptyStateRemainsShortcutOnly() {
        XCTAssertEqual(ChatsCanvasView.emptyStateTitle, "Start a conversation")
        XCTAssertEqual(ChatsCanvasView.emptyStateShortcutHint, "Shortcut: Shift-Command-N")
        XCTAssertNil(ChatsCanvasView.emptyStatePrimaryActionLabel)
    }
}
