@testable import CodexChatShared
import SwiftUI
import XCTest

@MainActor
final class ChatsCanvasViewStyleTests: XCTestCase {
    func testComposerSurfaceStyleTransparentDarkRemovesShadowAndKeepsLowerOpacity() {
        let style = ChatsCanvasView.composerSurfaceStyle(
            isTransparentThemeMode: true,
            colorScheme: .dark
        )

        XCTAssertEqual(style.fillOpacity, 0.62, accuracy: 0.0001)
        XCTAssertEqual(style.strokeMultiplier, 0.78, accuracy: 0.0001)
        XCTAssertEqual(style.shadowOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(style.shadowRadius, 0, accuracy: 0.0001)
        XCTAssertEqual(style.shadowYOffset, 0, accuracy: 0.0001)
    }

    func testComposerSurfaceStyleTransparentLightRemovesShadowAndKeepsLowerOpacity() {
        let style = ChatsCanvasView.composerSurfaceStyle(
            isTransparentThemeMode: true,
            colorScheme: .light
        )

        XCTAssertEqual(style.fillOpacity, 0.72, accuracy: 0.0001)
        XCTAssertEqual(style.strokeMultiplier, 0.78, accuracy: 0.0001)
        XCTAssertEqual(style.shadowOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(style.shadowRadius, 0, accuracy: 0.0001)
        XCTAssertEqual(style.shadowYOffset, 0, accuracy: 0.0001)
    }

    func testComposerSurfaceStyleOpaqueDarkKeepsShadowDepth() {
        let style = ChatsCanvasView.composerSurfaceStyle(
            isTransparentThemeMode: false,
            colorScheme: .dark
        )

        XCTAssertEqual(style.fillOpacity, 0.95, accuracy: 0.0001)
        XCTAssertEqual(style.strokeMultiplier, 0.95, accuracy: 0.0001)
        XCTAssertEqual(style.shadowOpacity, 0.12, accuracy: 0.0001)
        XCTAssertEqual(style.shadowRadius, 8, accuracy: 0.0001)
        XCTAssertEqual(style.shadowYOffset, 2, accuracy: 0.0001)
    }

    func testComposerSurfaceStyleOpaqueLightKeepsShadowDepth() {
        let style = ChatsCanvasView.composerSurfaceStyle(
            isTransparentThemeMode: false,
            colorScheme: .light
        )

        XCTAssertEqual(style.fillOpacity, 0.95, accuracy: 0.0001)
        XCTAssertEqual(style.strokeMultiplier, 0.95, accuracy: 0.0001)
        XCTAssertEqual(style.shadowOpacity, 0.05, accuracy: 0.0001)
        XCTAssertEqual(style.shadowRadius, 8, accuracy: 0.0001)
        XCTAssertEqual(style.shadowYOffset, 2, accuracy: 0.0001)
    }
}
