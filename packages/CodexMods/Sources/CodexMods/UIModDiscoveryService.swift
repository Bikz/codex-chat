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

            if Self.containsLegacyRightInspectorKey(in: definitionData) {
                throw UIModDiscoveryError.unsupportedLegacyKey("uiSlots.rightInspector")
            }

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
            description: "Sample extension mod for CodexChat modsBar workflows.",
            homepage: nil,
            repository: nil,
            checksum: nil
        )

        let theme = ModThemeOverride(
            typography: .init(titleSize: 21, bodySize: 14, captionSize: 12),
            spacing: .init(xSmall: 6, small: 10, medium: 16, large: 24),
            radius: .init(small: 8, medium: 14, large: 20),
            palette: .init(accentHex: "#10A37F", backgroundHex: "#F7F8F7", panelHex: "#FFFFFF"),
            materials: .init(panelMaterial: "thin", cardMaterial: "regular"),
            bubbles: .init(style: "glass", userBackgroundHex: "#10A37F", assistantBackgroundHex: "#FFFFFF"),
            iconography: .init(style: "sf-symbols")
        )
        let darkTheme = ModThemeOverride(
            palette: .init(accentHex: "#10A37F", backgroundHex: "#000000", panelHex: "#121212"),
            bubbles: .init(style: "glass", userBackgroundHex: "#10A37F", assistantBackgroundHex: "#1C1C1E")
        )

        let definition = UIModDefinition(
            schemaVersion: 1,
            manifest: manifest,
            theme: theme,
            darkTheme: darkTheme,
            hooks: [
                ModHookDefinition(
                    id: "turn-summary",
                    event: .turnCompleted,
                    handler: ModExtensionHandler(command: ["sh", "scripts/hook.sh"], cwd: "."),
                    permissions: .init(projectRead: true),
                    timeoutMs: 8000,
                    debounceMs: 0
                ),
            ],
            automations: [
                ModAutomationDefinition(
                    id: "daily-notes",
                    schedule: "0 9 * * *",
                    handler: ModExtensionHandler(command: ["sh", "scripts/automation.sh"], cwd: "."),
                    permissions: .init(projectRead: true, projectWrite: true, runWhenAppClosed: true),
                    timeoutMs: 60000
                ),
            ],
            uiSlots: .init(
                modsBar: .init(
                    enabled: true,
                    title: "Summary",
                    source: .init(type: "handlerOutput", hookID: "turn-summary")
                )
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(definition)
        try data.write(to: definitionURL, options: [.atomic])

        let packageManifest = ModPackageManifest(
            schemaVersion: 1,
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            author: manifest.author,
            license: manifest.license,
            homepage: manifest.homepage,
            repository: manifest.repository,
            entrypoints: ModEntrypoints(uiMod: "ui.mod.json"),
            permissions: ModPackageManifestLoader
                .requestedPermissions(for: definition)
                .sorted { $0.rawValue < $1.rawValue },
            compatibility: ModCompatibility(
                platforms: ["macos"],
                minCodexChatVersion: "0.1.0",
                maxCodexChatVersion: nil
            ),
            integrity: nil
        )
        let manifestURL = modDirectory.appendingPathComponent("codex.mod.json", isDirectory: false)
        let packageData = try encoder.encode(packageManifest)
        try packageData.write(to: manifestURL, options: [.atomic])

        let scriptsDirectory = modDirectory.appendingPathComponent("scripts", isDirectory: true)
        try fileManager.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        try writeScript(
            """
            #!/bin/sh
            read -r _INPUT
            echo '{"ok":true,"modsBar":{"title":"Thread Summary","markdown":"- Turn completed. Update this script with your own summary logic."}}'
            """,
            to: scriptsDirectory.appendingPathComponent("hook.sh", isDirectory: false)
        )
        try writeScript(
            """
            #!/bin/sh
            read -r _INPUT
            echo '{"ok":true,"log":"daily-notes automation tick"}'
            """,
            to: scriptsDirectory.appendingPathComponent("automation.sh", isDirectory: false)
        )

        let readmeURL = modDirectory.appendingPathComponent("README.md", isDirectory: false)
        let readme = """
        # \(manifest.name)

        This sample demonstrates:
        - `codex.mod.json` package manifest (install/distribution metadata)
        - `ui.mod.json` extension runtime configuration
        - `scripts/hook.sh` for `turn.completed` modsBar updates
        - `scripts/automation.sh` for scheduled automation jobs

        Start here:
        1. Edit `scripts/hook.sh` to produce a one-line summary for each turn.
        2. Adjust permissions/schedules in `ui.mod.json`.
        3. Reinstall from this folder or from your git repository URL in CodexChat.
        """
        try Data(readme.utf8).write(to: readmeURL, options: [.atomic])
        return definitionURL
    }

    private static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func containsLegacyRightInspectorKey(in definitionData: Data) -> Bool {
        guard
            let root = try? JSONSerialization.jsonObject(with: definitionData) as? [String: Any],
            let uiSlots = root["uiSlots"] as? [String: Any]
        else {
            return false
        }

        return uiSlots["rightInspector"] != nil
    }

    private func writeScript(_ script: String, to url: URL) throws {
        try Data(script.utf8).write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
