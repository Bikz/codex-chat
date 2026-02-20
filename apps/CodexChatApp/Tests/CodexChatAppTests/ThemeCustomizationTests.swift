import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import CodexMods
import XCTest

@MainActor
final class ThemeCustomizationTests: XCTestCase {
    func testResolvedThemeOverridePrefersUserCustomizationWhenEnabled() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.effectiveThemeOverride = ModThemeOverride(
            palette: .init(accentHex: "#11AA11", backgroundHex: "#F0F0F0", panelHex: "#FFFFFF", sidebarHex: "#EFEFEF")
        )
        model.userThemeCustomization = .init(
            isEnabled: true,
            accentHex: "#3366FF",
            sidebarHex: "#112233",
            backgroundHex: "#0D1117",
            panelHex: "#161B22",
            sidebarGradientHex: "#224466",
            chatGradientHex: "#335577",
            gradientStrength: 0.6
        )

        let resolved = model.resolvedLightThemeOverride
        XCTAssertEqual(resolved.resolvedPaletteAccentHex, "#3366FF")
        XCTAssertEqual(resolved.resolvedPaletteSidebarHex, "#112233")
        XCTAssertEqual(resolved.resolvedPaletteBackgroundHex, "#0D1117")
        XCTAssertEqual(resolved.resolvedPalettePanelHex, "#161B22")
    }

    func testResolvedThemeOverrideFallsBackToModPaletteWhenCustomizationDisabled() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.effectiveThemeOverride = ModThemeOverride(
            palette: .init(accentHex: "#11AA11", backgroundHex: "#F0F0F0", panelHex: "#FFFFFF", sidebarHex: "#EFEFEF")
        )
        model.userThemeCustomization = .init(
            isEnabled: false,
            accentHex: "#3366FF",
            sidebarHex: "#112233",
            backgroundHex: "#0D1117",
            panelHex: "#161B22",
            sidebarGradientHex: "#224466",
            chatGradientHex: "#335577",
            gradientStrength: 0.6
        )

        let resolved = model.resolvedLightThemeOverride
        XCTAssertEqual(resolved.resolvedPaletteAccentHex, "#11AA11")
        XCTAssertEqual(resolved.resolvedPaletteSidebarHex, "#EFEFEF")
        XCTAssertEqual(resolved.resolvedPaletteBackgroundHex, "#F0F0F0")
        XCTAssertEqual(resolved.resolvedPalettePanelHex, "#FFFFFF")
    }

    func testResolvedThemeOverrideKeepsSystemDefaultsWhenEnabledWithoutOverrides() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.effectiveDarkThemeOverride = ModThemeOverride(
            palette: .init(accentHex: "#11AA11", backgroundHex: "#000000", panelHex: "#121212", sidebarHex: "#0A0A0A")
        )
        model.userThemeCustomization = .init(isEnabled: true)

        let resolved = model.resolvedDarkThemeOverride
        XCTAssertEqual(resolved.resolvedPaletteAccentHex, "#11AA11")
        XCTAssertEqual(resolved.resolvedPaletteSidebarHex, "#0A0A0A")
        XCTAssertEqual(resolved.resolvedPaletteBackgroundHex, "#000000")
        XCTAssertEqual(resolved.resolvedPalettePanelHex, "#121212")
    }

    func testRestoreUserThemeCustomizationReadsPreference() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-theme-restore-\(UUID().uuidString)", isDirectory: true)
        let dbURL = root.appendingPathComponent("metadata.sqlite", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        let expected = AppModel.UserThemeCustomization(
            isEnabled: true,
            accentHex: "#88CCFF",
            sidebarHex: "#0E1A2B",
            backgroundHex: "#101826",
            panelHex: "#18243A",
            sidebarGradientHex: "#2E4B68",
            chatGradientHex: "#3A5A78",
            gradientStrength: 0.52
        )

        let encoded = try JSONEncoder().encode(expected)
        try await repositories.preferenceRepository.setPreference(
            key: .userThemeCustomizationV1,
            value: String(data: encoded, encoding: .utf8) ?? "{}"
        )

        await model.restoreUserThemeCustomizationIfNeeded()
        XCTAssertEqual(model.userThemeCustomization, expected)
    }

    func testRestoreUserThemeCustomizationMigratesLegacyDefaultOverrideToSystemDefault() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-theme-legacy-\(UUID().uuidString)", isDirectory: true)
        let dbURL = root.appendingPathComponent("metadata.sqlite", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        let legacyJSON = """
        {
          "isEnabled": true,
          "accentHex": "#10A37F",
          "sidebarHex": "#F5F5F5",
          "backgroundHex": "#F9F9F9",
          "panelHex": "#FFFFFF",
          "sidebarGradientHex": "#8AA2B2",
          "chatGradientHex": "#B9C6D0",
          "gradientStrength": 0.35
        }
        """

        try await repositories.preferenceRepository.setPreference(
            key: .userThemeCustomizationV1,
            value: legacyJSON
        )

        await model.restoreUserThemeCustomizationIfNeeded()
        XCTAssertEqual(model.userThemeCustomization, .default)
    }
}
