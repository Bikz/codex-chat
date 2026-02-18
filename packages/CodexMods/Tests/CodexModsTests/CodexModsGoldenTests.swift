@testable import CodexMods
import Foundation
import XCTest

final class CodexModsGoldenTests: XCTestCase {
    func testThemeOverrideMergeMatchesGoldenJSON() throws {
        let decoder = JSONDecoder()
        let base = try decoder.decode(ModThemeOverride.self, from: try fixtureData("theme-base.json"))
        let overlay = try decoder.decode(ModThemeOverride.self, from: try fixtureData("theme-overlay.json"))

        let merged = base.merged(with: overlay)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let actual = String(decoding: try encoder.encode(merged), as: UTF8.self)
        let expected = String(decoding: try fixtureData("theme-merged.json"), as: UTF8.self)

        let normalizedActual = actual.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        let normalizedExpected = expected.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"

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
