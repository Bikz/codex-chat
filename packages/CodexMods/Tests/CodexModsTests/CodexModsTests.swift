import XCTest
@testable import CodexMods

final class CodexModsTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexModsPackage.version, "0.1.0")
    }

    func testThemeOverrideMergePrefersOverlayValues() {
        let base = ModThemeOverride(
            typography: .init(titleSize: 18, bodySize: 13, captionSize: 11),
            palette: .init(accentHex: "#111111", backgroundHex: "#222222", panelHex: "#333333"),
            materials: .init(panelMaterial: "thin", cardMaterial: "regular")
        )

        let overlay = ModThemeOverride(
            typography: .init(titleSize: nil, bodySize: 15, captionSize: nil),
            palette: .init(accentHex: "#FF5500", backgroundHex: nil, panelHex: "#000000"),
            materials: .init(panelMaterial: nil, cardMaterial: "thick")
        )

        let merged = base.merged(with: overlay)
        XCTAssertEqual(merged.palette?.accentHex, "#FF5500")
        XCTAssertEqual(merged.palette?.backgroundHex, "#222222")
        XCTAssertEqual(merged.palette?.panelHex, "#000000")
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
    }
}
