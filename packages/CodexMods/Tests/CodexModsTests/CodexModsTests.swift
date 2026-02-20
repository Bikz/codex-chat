@testable import CodexMods
import XCTest

final class CodexModsTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexModsPackage.version, "0.1.0")
    }

    func testThemeOverrideMergePrefersOverlayValues() {
        let base = ModThemeOverride(
            typography: .init(titleSize: 18, bodySize: 13, captionSize: 11),
            palette: .init(accentHex: "#111111", backgroundHex: "#222222", panelHex: "#333333", sidebarHex: "#444444"),
            materials: .init(panelMaterial: "thin", cardMaterial: "regular")
        )

        let overlay = ModThemeOverride(
            typography: .init(titleSize: nil, bodySize: 15, captionSize: nil),
            palette: .init(accentHex: "#FF5500", backgroundHex: nil, panelHex: "#000000", sidebarHex: "#777777"),
            materials: .init(panelMaterial: nil, cardMaterial: "thick")
        )

        let merged = base.merged(with: overlay)
        XCTAssertEqual(merged.palette?.accentHex, "#FF5500")
        XCTAssertEqual(merged.palette?.backgroundHex, "#222222")
        XCTAssertEqual(merged.palette?.panelHex, "#000000")
        XCTAssertEqual(merged.palette?.sidebarHex, "#777777")
        XCTAssertEqual(merged.typography?.titleSize, 18)
        XCTAssertEqual(merged.typography?.bodySize, 15)
        XCTAssertEqual(merged.materials?.panelMaterial, "thin")
        XCTAssertEqual(merged.materials?.cardMaterial, "thick")
    }

    func testModDefinitionDecodes() throws {
        let json = """
        {
          "schemaVersion": 1,
          "manifest": {
            "id": "glass-green",
            "name": "Glass Green",
            "version": "1.0.0",
            "author": "Example",
            "license": "MIT"
          },
          "theme": {
            "palette": {
              "accentHex": "#00FF00",
              "backgroundHex": "#000000",
              "panelHex": "#111111"
            },
            "materials": {
              "panelMaterial": "thin",
              "cardMaterial": "regular"
            }
          },
          "darkTheme": {
            "palette": {
              "backgroundHex": "#000000",
              "panelHex": "#121212"
            }
          }
        }
        """

        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UIModDefinition.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.manifest.id, "glass-green")
        XCTAssertEqual(decoded.theme.palette?.accentHex, "#00FF00")
        XCTAssertEqual(decoded.theme.materials?.panelMaterial, "thin")
        XCTAssertEqual(decoded.darkTheme?.palette?.backgroundHex, "#000000")
    }

    func testWithoutColorOverridesRemovesPaletteAndBubbleColors() {
        let base = ModThemeOverride(
            accentHex: "#AA0000",
            backgroundHex: "#BB0000",
            panelHex: "#CC0000",
            sidebarHex: "#DD0000",
            typography: .init(titleSize: 20, bodySize: 15, captionSize: 12),
            spacing: .init(xSmall: 5, small: 9, medium: 14, large: 22),
            radius: .init(small: 7, medium: 12, large: 18),
            palette: .init(accentHex: "#DD0000", backgroundHex: "#EE0000", panelHex: "#FF0000", sidebarHex: "#111111"),
            materials: .init(panelMaterial: "thin", cardMaterial: "regular"),
            bubbles: .init(style: "glass", userBackgroundHex: "#101010", assistantBackgroundHex: "#202020"),
            iconography: .init(style: "sf-symbols")
        )

        let stripped = base.withoutColorOverrides()
        XCTAssertNil(stripped.accentHex)
        XCTAssertNil(stripped.backgroundHex)
        XCTAssertNil(stripped.panelHex)
        XCTAssertNil(stripped.sidebarHex)
        XCTAssertNil(stripped.palette)
        XCTAssertEqual(stripped.bubbles?.style, "glass")
        XCTAssertNil(stripped.bubbles?.userBackgroundHex)
        XCTAssertNil(stripped.bubbles?.assistantBackgroundHex)
        XCTAssertEqual(stripped.typography?.bodySize, 15)
        XCTAssertEqual(stripped.spacing?.medium, 14)
        XCTAssertEqual(stripped.materials?.cardMaterial, "regular")
    }

    func testResolvedDarkOverrideMergesDarkColorsAndKeepsNonColorOverrides() {
        let light = ModThemeOverride(
            typography: .init(titleSize: 19, bodySize: 14, captionSize: 12),
            palette: .init(accentHex: "#10A37F", backgroundHex: "#F7F8F7", panelHex: "#FFFFFF"),
            materials: .init(panelMaterial: "thin", cardMaterial: "regular"),
            bubbles: .init(style: "solid", userBackgroundHex: "#10A37F", assistantBackgroundHex: "#FFFFFF")
        )
        let dark = ModThemeOverride(
            palette: .init(accentHex: "#10A37F", backgroundHex: "#000000", panelHex: "#121212"),
            bubbles: .init(style: "glass", userBackgroundHex: "#10A37F", assistantBackgroundHex: "#1C1C1E")
        )

        let resolved = light.resolvedDarkOverride(using: dark)
        XCTAssertEqual(resolved.typography?.titleSize, 19)
        XCTAssertEqual(resolved.materials?.panelMaterial, "thin")
        XCTAssertEqual(resolved.palette?.backgroundHex, "#000000")
        XCTAssertEqual(resolved.palette?.panelHex, "#121212")
        XCTAssertEqual(resolved.bubbles?.style, "glass")
        XCTAssertEqual(resolved.bubbles?.assistantBackgroundHex, "#1C1C1E")
    }

    func testSchemaV1MalformedExtensionFieldsStillDecodeTheme() throws {
        let json = """
        {
          "schemaVersion": 1,
          "manifest": {
            "id": "v1-mod",
            "name": "V1 Mod",
            "version": "1.0.0"
          },
          "theme": {
            "palette": {
              "accentHex": "#10A37F"
            }
          },
          "hooks": {
            "invalid": true
          },
          "automations": "invalid",
          "uiSlots": 123
        }
        """

        let decoded = try JSONDecoder().decode(UIModDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.manifest.id, "v1-mod")
        XCTAssertEqual(decoded.theme.palette?.accentHex, "#10A37F")
        XCTAssertTrue(decoded.hooks.isEmpty)
        XCTAssertTrue(decoded.automations.isEmpty)
        XCTAssertNil(decoded.uiSlots)
    }
}
