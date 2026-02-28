@testable import CodexChatShared
import XCTest

@MainActor
final class SidebarAndDraftRegressionTests: XCTestCase {
    func testSidebarProjectsPreviewStorageAndOptionsAreStable() {
        XCTAssertEqual(SidebarView.projectsPreviewCountStorageKey, "codexchat.sidebar.projectsPreviewCount")
        XCTAssertEqual(SidebarView.projectsPreviewCountOptions, [3, 5, 8, 12])
        XCTAssertEqual(SidebarView.threadFilterStorageKey, "codexchat.sidebar.threadFilter")
        XCTAssertEqual(SidebarView.showRecentsStorageKey, "codexchat.sidebar.showRecents")
    }

    func testSettingsAppearanceUsesSidebarProjectsPreviewConfig() {
        XCTAssertEqual(SettingsView.sidebarProjectsPreviewStorageKey, SidebarView.projectsPreviewCountStorageKey)
        XCTAssertEqual(SettingsView.sidebarProjectsPreviewOptions, SidebarView.projectsPreviewCountOptions)
        XCTAssertEqual(SettingsView.sidebarShowRecentsStorageKey, SidebarView.showRecentsStorageKey)
    }

    func testDraftEmptyStateRemainsShortcutOnly() {
        XCTAssertEqual(ChatsCanvasView.emptyStateTitle, "Start a conversation")
        XCTAssertEqual(ChatsCanvasView.emptyStateShortcutHint, "Shortcut: Shift-Command-N")
        XCTAssertNil(ChatsCanvasView.emptyStatePrimaryActionLabel)
    }

    func testComposerPrimaryControlsRemainModelAndReasoningOnly() {
        XCTAssertEqual(ChatsCanvasView.composerPrimaryVisibleControlIDs, ["model", "reasoning"])
        XCTAssertEqual(
            ChatsCanvasView.composerPopoverControlIDs,
            ["web-search", "memory-mode", "execution-permissions"]
        )
    }
}
