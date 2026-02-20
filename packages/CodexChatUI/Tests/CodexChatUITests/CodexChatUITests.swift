@testable import CodexChatUI
import CodexMods
import XCTest

final class CodexChatUITests: XCTestCase {
    func testTokenOverrideInjectionAppliesPaletteOverrides() {
        let baseline = DesignTokens.default
        let override = ModThemeOverride(
            accentHex: "#FF5500",
            backgroundHex: "#000000",
            panelHex: "#101010",
            sidebarHex: "#080808"
        )

        let injected = baseline.applying(override: override)

        XCTAssertEqual(injected.palette.accentHex, "#FF5500")
        XCTAssertEqual(injected.palette.backgroundHex, "#000000")
        XCTAssertEqual(injected.palette.panelHex, "#101010")
        XCTAssertEqual(injected.palette.sidebarHex, "#080808")
    }

    @MainActor
    func testThemeProviderResetRestoresBaseline() {
        let provider = ThemeProvider(tokens: .default)
        provider.apply(override: ModThemeOverride(accentHex: "#AA00CC"))
        XCTAssertEqual(provider.tokens.palette.accentHex, "#AA00CC")

        provider.reset()
        XCTAssertEqual(provider.tokens, .default)
    }

    func testSystemBaselinesExposeExpectedPaletteAndBubbleDefaults() {
        XCTAssertEqual(DesignTokens.systemLight.palette.backgroundHex, "#F9F9F9")
        XCTAssertEqual(DesignTokens.systemLight.palette.panelHex, "#FFFFFF")
        XCTAssertEqual(DesignTokens.systemLight.bubbles.assistantBackgroundHex, "#FFFFFF")

        XCTAssertEqual(DesignTokens.systemDark.palette.backgroundHex, "#000000")
        XCTAssertEqual(DesignTokens.systemDark.palette.panelHex, "#121212")
        XCTAssertEqual(DesignTokens.systemDark.bubbles.assistantBackgroundHex, "#1C1C1E")
    }

    func testDefaultTokensAliasSystemLightForCompatibility() {
        XCTAssertEqual(DesignTokens.default, DesignTokens.systemLight)
    }
}
