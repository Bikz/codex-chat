import CryptoKit
import Foundation

public final class UIModDiscoveryService: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func discoverMods(in rootPath: String, scope: ModScope) throws -> [DiscoveredUIMod] {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }

        var discovered: [DiscoveredUIMod] = []

        let rootCandidates = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for candidate in rootCandidates {
            let isDirectory = (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }

            let definitionURL = candidate.appendingPathComponent("ui.mod.json", isDirectory: false)
            guard fileManager.fileExists(atPath: definitionURL.path) else { continue }

            let definitionData = try Data(contentsOf: definitionURL)
            let checksum = Self.sha256Hex(of: definitionData)

            let definition: UIModDefinition
            do {
                let decoder = JSONDecoder()
                definition = try decoder.decode(UIModDefinition.self, from: definitionData)
            } catch {
                throw UIModDiscoveryError.unreadableDefinition(error.localizedDescription)
            }

            guard definition.schemaVersion == 1 else {
                throw UIModDiscoveryError.invalidSchemaVersion(definition.schemaVersion)
            }
            guard !definition.manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UIModDiscoveryError.invalidManifestID(definition.manifest.id)
            }

            if let expected = definition.manifest.checksum?.trimmingCharacters(in: .whitespacesAndNewlines),
               !expected.isEmpty
            {
                let normalizedExpected = expected.lowercased()
                let normalizedActual = "sha256:\(checksum)"
                if normalizedExpected != normalizedActual {
                    throw UIModDiscoveryError.invalidChecksum(expected: expected, actual: normalizedActual)
                }
            }

            discovered.append(
                DiscoveredUIMod(
                    scope: scope,
                    directoryPath: candidate.standardizedFileURL.path,
                    definitionPath: definitionURL.standardizedFileURL.path,
                    definition: definition,
                    computedChecksum: "sha256:\(checksum)"
                )
            )
        }

        return discovered.sorted {
            $0.definition.manifest.name.localizedCaseInsensitiveCompare($1.definition.manifest.name) == .orderedAscending
        }
    }

    public func writeSampleMod(to directoryPath: String, name: String) throws -> URL {
        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let safe = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        let modDirectory = directoryURL.appendingPathComponent(safe.isEmpty ? "sample-mod" : safe, isDirectory: true)
        try fileManager.createDirectory(at: modDirectory, withIntermediateDirectories: true)

        let definitionURL = modDirectory.appendingPathComponent("ui.mod.json")
        if fileManager.fileExists(atPath: definitionURL.path) {
            return definitionURL
        }

        let manifest = UIModManifest(
            id: safe.isEmpty ? "sample-mod" : safe.lowercased(),
            name: safe.isEmpty ? "Sample Mod" : safe,
            version: "0.1.0",
            author: nil,
            license: "MIT",
            description: "Example theme override for CodexChat.",
            homepage: nil,
            repository: nil,
            checksum: nil
        )

        let theme = ModThemeOverride(
            typography: .init(titleSize: 21, bodySize: 14, captionSize: 12),
            spacing: .init(xSmall: 6, small: 10, medium: 16, large: 24),
            radius: .init(small: 8, medium: 14, large: 20),
            palette: .init(accentHex: "#2E7D32", backgroundHex: "#F7F8F7", panelHex: "#FFFFFF"),
            materials: .init(panelMaterial: "thin", cardMaterial: "regular"),
            bubbles: .init(style: "glass", userBackgroundHex: "#2E7D32", assistantBackgroundHex: "#FFFFFF"),
            iconography: .init(style: "sf-symbols")
        )

        let definition = UIModDefinition(schemaVersion: 1, manifest: manifest, theme: theme)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(definition)
        try data.write(to: definitionURL, options: [.atomic])
        return definitionURL
    }

    private static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
