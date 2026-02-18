@testable import CodexMods
import Foundation
import XCTest

final class CodexModsGoldenTests: XCTestCase {
    func testThemeOverrideMergeMatchesGoldenJSON() throws {
        let decoder = JSONDecoder()
        let baseData = try fixtureData("theme-base.json")
        let overlayData = try fixtureData("theme-overlay.json")

        let base = try decoder.decode(ModThemeOverride.self, from: baseData)
        let overlay = try decoder.decode(ModThemeOverride.self, from: overlayData)

        let merged = base.merged(with: overlay)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let actualData = try encoder.encode(merged)
        let expectedData = try fixtureData("theme-merged.json")
        let expected = try decoder.decode(ModThemeOverride.self, from: expectedData)
        let expectedCanonicalData = try encoder.encode(expected)

        let actual = try XCTUnwrap(String(data: actualData, encoding: .utf8))
        let expectedCanonical = try XCTUnwrap(String(data: expectedCanonicalData, encoding: .utf8))

        let normalizedActual = actual.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        let normalizedExpected = expectedCanonical.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"

        XCTAssertEqual(normalizedActual, normalizedExpected)
    }

    func testDarkResolveWithoutDarkThemeStripsOnlyColorOverrides() throws {
        let decoder = JSONDecoder()
        let baseData = try fixtureData("theme-dark-resolve-base.json")
        let base = try decoder.decode(ModThemeOverride.self, from: baseData)

        let resolved = base.resolvedDarkOverride(using: .init())

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let actualData = try encoder.encode(resolved)
        let expectedData = try fixtureData("theme-dark-resolve-expected.json")
        let expected = try decoder.decode(ModThemeOverride.self, from: expectedData)
        let expectedCanonicalData = try encoder.encode(expected)

        let actual = try XCTUnwrap(String(data: actualData, encoding: .utf8))
        let expectedCanonical = try XCTUnwrap(String(data: expectedCanonicalData, encoding: .utf8))

        let normalizedActual = actual.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        let normalizedExpected = expectedCanonical.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"

        XCTAssertEqual(normalizedActual, normalizedExpected)
    }

    private func fixtureData(_ fileName: String) throws -> Data {
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw NSError(domain: "CodexModsGoldenTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture: \(fileName)"])
        }
        return try Data(contentsOf: url)
    }
}
