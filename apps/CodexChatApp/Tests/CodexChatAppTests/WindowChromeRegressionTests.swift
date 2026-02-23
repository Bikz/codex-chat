import AppKit
@testable import CodexChatShared
import XCTest

@MainActor
final class WindowChromeRegressionTests: XCTestCase {
    func testConfigureDesktopWindowAppliesUnifiedChromeInOpaqueMode() {
        let window = makeWindow()

        configureDesktopWindow(window, isTransparent: false)

        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertGreaterThanOrEqual(window.minSize.width, 600)
        XCTAssertGreaterThanOrEqual(window.minSize.height, 400)
        XCTAssertGreaterThan(window.maxSize.width, 1_000_000)
        XCTAssertGreaterThan(window.maxSize.height, 1_000_000)
        XCTAssertEqual(window.toolbarStyle, .unified)
        XCTAssertEqual(window.toolbar?.showsBaselineSeparator, false)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertTrue(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, NSColor.windowBackgroundColor)
    }

    func testConfigureDesktopWindowUsesClearBackgroundInTransparentMode() {
        let window = makeWindow()

        configureDesktopWindow(window, isTransparent: true)

        XCTAssertEqual(window.toolbarStyle, .unified)
        XCTAssertEqual(window.toolbar?.showsBaselineSeparator, false)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
    }

    func testConfigureSettingsWindowAppliesUnifiedChromeContract() {
        let window = makeWindow()

        configureSettingsWindow(window, isTransparent: false)

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.toolbarStyle, .unified)
        XCTAssertEqual(window.toolbar?.showsBaselineSeparator, false)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertTrue(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, NSColor.windowBackgroundColor)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.toolbar = NSToolbar(identifier: "window-chrome-regression-tests")
        return window
    }
}
