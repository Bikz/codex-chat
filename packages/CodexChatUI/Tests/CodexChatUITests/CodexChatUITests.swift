@testable import CodexChatUI
import CodexMods
import XCTest

final class CodexChatUITests: XCTestCase {
    func testTokenOverrideInjectionAppliesPaletteOverrides() {
        let baseline = DesignTokens.default
        let override = ModThemeOverride(
            accentHex: "#FF5500",
            backgroundHex: "#000000",
            panelHex: "#101010"
        )

        let injected = baseline.applying(override: override)

        XCTAssertEqual(injected.palette.accentHex, "#FF5500")
        XCTAssertEqual(injected.palette.backgroundHex, "#000000")
        XCTAssertEqual(injected.palette.panelHex, "#101010")
    }

    @MainActor
    func testThemeProviderResetRestoresBaseline() {
        let provider = ThemeProvider(tokens: .default)
        provider.apply(override: ModThemeOverride(accentHex: "#AA00CC"))
        XCTAssertEqual(provider.tokens.palette.accentHex, "#AA00CC")

        provider.reset()
        XCTAssertEqual(provider.tokens, .default)
    }
}
