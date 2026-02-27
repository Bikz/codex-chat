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

    func testModsBarOverlayWidthsScaleFromRailToExpanded() {
        let railWidth = ChatsCanvasView.modsBarOverlayWidth(for: .rail)
        let peekWidth = ChatsCanvasView.modsBarOverlayWidth(for: .peek)
        let expandedWidth = ChatsCanvasView.modsBarOverlayWidth(for: .expanded)

        XCTAssertEqual(railWidth, 56, accuracy: 0.0001)
        XCTAssertEqual(peekWidth, 304, accuracy: 0.0001)
        XCTAssertEqual(expandedWidth, 388, accuracy: 0.0001)
        XCTAssertLessThan(railWidth, peekWidth)
        XCTAssertLessThan(peekWidth, expandedWidth)
    }

    func testModsBarDockedWidthClampsToContainerBudget() {
        let peekNarrow = ChatsCanvasView.modsBarDockedWidth(for: .peek, containerWidth: 820)
        let peekWide = ChatsCanvasView.modsBarDockedWidth(for: .peek, containerWidth: 1600)
        let expandedNarrow = ChatsCanvasView.modsBarDockedWidth(for: .expanded, containerWidth: 820)
        let expandedWide = ChatsCanvasView.modsBarDockedWidth(for: .expanded, containerWidth: 1600)

        XCTAssertLessThan(peekNarrow, ChatsCanvasView.modsBarOverlayWidth(for: .peek))
        XCTAssertEqual(peekWide, ChatsCanvasView.modsBarOverlayWidth(for: .peek), accuracy: 0.0001)
        XCTAssertLessThan(expandedNarrow, ChatsCanvasView.modsBarOverlayWidth(for: .expanded))
        XCTAssertEqual(expandedWide, ChatsCanvasView.modsBarOverlayWidth(for: .expanded), accuracy: 0.0001)
    }

    func testModsBarOverlayStyleKeepsLayeredPanelGeometryStable() {
        let style = ChatsCanvasView.modsBarOverlayStyle
        XCTAssertEqual(style.cornerRadius, 16, accuracy: 0.0001)
        XCTAssertEqual(style.layerOffset, 8, accuracy: 0.0001)
    }

    func testFollowUpStatusPresentationSuppressesFailureCopy() {
        let presentation = ChatsCanvasView.followUpStatusPresentation(
            for: "Failed to send follow-up: No draft chat is active."
        )
        XCTAssertNil(presentation)
    }

    func testFollowUpStatusPresentationTreatsQueuedCopyAsInfo() {
        let presentation = ChatsCanvasView.followUpStatusPresentation(
            for: "Queued follow-up. It will auto-send when the runtime is idle."
        )
        XCTAssertEqual(
            presentation,
            .info("Queued follow-up. It will auto-send when the runtime is idle.")
        )
    }

    func testFollowUpStatusPresentationDropsEmptyMessages() {
        XCTAssertNil(ChatsCanvasView.followUpStatusPresentation(for: "   "))
        XCTAssertNil(ChatsCanvasView.followUpStatusPresentation(for: nil))
    }
}
