@testable import CodexMods
import CryptoKit
import Darwin
import Foundation
import XCTest

final class ModInstallServiceTests: XCTestCase {
    func testManifestLoaderRejectsPackageMissingCodexManifest() throws {
        let root = try makeTempDirectory(prefix: "codexmods-missing-manifest")
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try writeUIMod(
            to: root,
            id: "acme.thread-summary",
            name: "Thread Summary",
            version: "1.0.0",
            permissions: .init(projectRead: true)
        )

        XCTAssertThrowsError(try ModPackageManifestLoader.load(packageRootURL: root)) { error in
            guard case ModPackageValidationError.missingPackageManifest = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(error.localizedDescription.contains("codex.mod.json"))
        }
    }

    func testManifestLoaderRejectsUndeclaredPermissions() throws {
        let root = try makeTempDirectory(prefix: "codexmods-perms")
        defer { try? FileManager.default.removeItem(at: root) }

        let definition = try writeUIMod(
            to: root,
            id: "acme.net-mod",
            name: "Network Mod",
            version: "1.0.0",
            permissions: .init(network: true)
        )
        try writePackageManifest(
            to: root,
            ModPackageManifest(
                id: definition.manifest.id,
                name: definition.manifest.name,
                version: definition.manifest.version,
                permissions: [.projectRead]
            )
        )

        XCTAssertThrowsError(try ModPackageManifestLoader.load(packageRootURL: root)) { error in
            guard case let ModPackageValidationError.permissionsUndeclared(missing) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(missing, [.network])
        }
    }

    func testManifestLoaderRejectsUnsafeEntrypointPath() throws {
        let root = try makeTempDirectory(prefix: "codexmods-entrypoint")
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try writeUIMod(
            to: root,
            id: "acme.bad-entrypoint",
            name: "Bad Entrypoint",
            version: "1.0.0",
            permissions: .init()
        )
        try writePackageManifest(
            to: root,
            ModPackageManifest(
                id: "acme.bad-entrypoint",
                name: "Bad Entrypoint",
                version: "1.0.0",
                entrypoints: .init(uiMod: "../ui.mod.json"),
                permissions: []
            )
        )

        XCTAssertThrowsError(try ModPackageManifestLoader.load(packageRootURL: root)) { error in
            guard case ModPackageValidationError.invalidEntrypointPath = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testManifestLoaderValidatesIntegrityChecksum() throws {
        let root = try makeTempDirectory(prefix: "codexmods-integrity")
        defer { try? FileManager.default.removeItem(at: root) }

        let definition = try writeUIMod(
            to: root,
            id: "acme.integrity",
            name: "Integrity Mod",
            version: "1.0.0",
            permissions: .init()
        )
        try writePackageManifest(
            to: root,
            ModPackageManifest(
                id: definition.manifest.id,
                name: definition.manifest.name,
                version: definition.manifest.version,
                permissions: [],
                integrity: .init(uiModSha256: "sha256:deadbeef")
            )
        )

        XCTAssertThrowsError(try ModPackageManifestLoader.load(packageRootURL: root)) { error in
            guard case ModPackageValidationError.integrityMismatch = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testInstallServiceInstallsLocalPackage() throws {
        let sourceRoot = try makeTempDirectory(prefix: "codexmods-install-src")
        let destinationRoot = try makeTempDirectory(prefix: "codexmods-install-dst")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: destinationRoot)
        }

        let definition = try writeUIMod(
            to: sourceRoot,
            id: "acme.installable",
            name: "Installable Mod",
            version: "1.0.0",
            permissions: .init(projectRead: true, projectWrite: true)
        )
        let checksum = try checksumForUIMod(at: sourceRoot)
        try writePackageManifest(
            to: sourceRoot,
            ModPackageManifest(
                id: definition.manifest.id,
                name: definition.manifest.name,
                version: definition.manifest.version,
                permissions: [.projectRead, .projectWrite],
                integrity: .init(uiModSha256: checksum)
            )
        )

        let service = ModInstallService()
        let result = try service.install(source: sourceRoot.path, destinationRootURL: destinationRoot)

        XCTAssertEqual(result.manifestSource, .codexManifest)
        XCTAssertEqual(result.definition.manifest.id, definition.manifest.id)
        XCTAssertEqual(result.requestedPermissions, [.projectRead, .projectWrite])
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.installedDirectoryPath))
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testInstallServicePreviewReturnsManifestAndPermissions() throws {
        let sourceRoot = try makeTempDirectory(prefix: "codexmods-preview-src")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let definition = try writeUIMod(
            to: sourceRoot,
            id: "acme.preview",
            name: "Preview Mod",
            version: "1.2.3",
            permissions: .init(projectRead: true, network: true)
        )
        try writePackageManifest(
            to: sourceRoot,
            ModPackageManifest(
                id: definition.manifest.id,
                name: definition.manifest.name,
                version: definition.manifest.version,
                permissions: [.network, .projectRead],
                compatibility: .init(platforms: ["macos"], minCodexChatVersion: "0.1.0")
            )
        )

        let service = ModInstallService()
        let preview = try service.preview(source: sourceRoot.path)

        XCTAssertEqual(preview.packageManifest.id, "acme.preview")
        XCTAssertEqual(preview.packageManifest.version, "1.2.3")
        XCTAssertEqual(preview.requestedPermissions, [.projectRead, .network])
        XCTAssertTrue(preview.warnings.isEmpty)
    }

    func testInstallServiceRejectsSourceMissingCodexManifest() throws {
        let sourceRoot = try makeTempDirectory(prefix: "codexmods-missing-codex")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        _ = try writeUIMod(
            to: sourceRoot,
            id: "acme.legacy-only-ui",
            name: "Legacy Only UI",
            version: "1.0.0",
            permissions: .init(projectRead: true)
        )

        let service = ModInstallService()
        XCTAssertThrowsError(try service.preview(source: sourceRoot.path)) { error in
            guard let installError = error as? ModInstallServiceError else {
                return XCTFail("Unexpected error: \(error)")
            }
            guard case .packageRootNotFound = installError else {
                return XCTFail("Expected packageRootNotFound, got \(installError)")
            }
            XCTAssertTrue(installError.localizedDescription.contains("codex.mod.json"))
        }
    }

    func testInstallServiceInstallsFromGitHubTreeSubdirectoryURL() throws {
        let repoFixtureRoot = try makeTempDirectory(prefix: "codexmods-github-tree-src")
        let destinationRoot = try makeTempDirectory(prefix: "codexmods-github-tree-dst")
        defer {
            try? FileManager.default.removeItem(at: repoFixtureRoot)
            try? FileManager.default.removeItem(at: destinationRoot)
        }

        let packageRoot = repoFixtureRoot
            .appendingPathComponent("mods/personal-notes", isDirectory: true)
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)

        let definition = try writeUIMod(
            to: packageRoot,
            id: "acme.personal-notes",
            name: "Personal Notes",
            version: "1.0.0",
            permissions: .init(projectRead: true, projectWrite: true)
        )
        let checksum = try checksumForUIMod(at: packageRoot)
        try writePackageManifest(
            to: packageRoot,
            ModPackageManifest(
                id: definition.manifest.id,
                name: definition.manifest.name,
                version: definition.manifest.version,
                permissions: [.projectRead, .projectWrite],
                integrity: .init(uiModSha256: checksum)
            )
        )

        let processRunner: ModInstallService.ProcessRunner = { argv, _ in
            if argv == ["git", "ls-remote", "--heads", "--tags", "https://github.com/acme/mod-pack.git"] {
                return """
                1111111111111111111111111111111111111111\trefs/heads/main
                """
            }

            guard argv.count >= 2,
                  argv[0] == "git",
                  argv[1] == "clone",
                  argv.contains("--branch"),
                  argv.contains("main"),
                  argv.contains("https://github.com/acme/mod-pack.git"),
                  let destinationPath = argv.last
            else {
                throw ModInstallServiceError.commandFailed(command: argv.joined(separator: " "), output: "Unexpected command")
            }
            let destinationURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            try Self.copyDirectoryContents(from: repoFixtureRoot, to: destinationURL)
            return ""
        }

        let service = ModInstallService(processRunner: processRunner)
        let sourceURL = "https://github.com/acme/mod-pack/tree/main/mods/personal-notes"
        let result = try service.install(source: sourceURL, destinationRootURL: destinationRoot)

        XCTAssertEqual(result.definition.manifest.id, "acme.personal-notes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.installedDirectoryPath))
    }

    func testInstallServiceInstallsFromGitHubTreeSubdirectoryURLWithSlashBranch() throws {
        let repoFixtureRoot = try makeTempDirectory(prefix: "codexmods-github-tree-slash-src")
        let destinationRoot = try makeTempDirectory(prefix: "codexmods-github-tree-slash-dst")
        defer {
            try? FileManager.default.removeItem(at: repoFixtureRoot)
            try? FileManager.default.removeItem(at: destinationRoot)
        }

        let packageRoot = repoFixtureRoot
            .appendingPathComponent("mods/personal-notes", isDirectory: true)
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)

        let definition = try writeUIMod(
            to: packageRoot,
            id: "acme.personal-notes",
            name: "Personal Notes",
            version: "1.0.0",
            permissions: .init(projectRead: true, projectWrite: true)
        )
        let checksum = try checksumForUIMod(at: packageRoot)
        try writePackageManifest(
            to: packageRoot,
            ModPackageManifest(
                id: definition.manifest.id,
                name: definition.manifest.name,
                version: definition.manifest.version,
                permissions: [.projectRead, .projectWrite],
                integrity: .init(uiModSha256: checksum)
            )
        )

        let processRunner: ModInstallService.ProcessRunner = { argv, _ in
            if argv == ["git", "ls-remote", "--heads", "--tags", "https://github.com/acme/mod-pack.git"] {
                return """
                1111111111111111111111111111111111111111\trefs/heads/main
                2222222222222222222222222222222222222222\trefs/heads/feature/release
                """
            }

            guard argv.count >= 2,
                  argv[0] == "git",
                  argv[1] == "clone",
                  argv.contains("--branch"),
                  argv.contains("feature/release"),
                  argv.contains("https://github.com/acme/mod-pack.git"),
                  let destinationPath = argv.last
            else {
                throw ModInstallServiceError.commandFailed(command: argv.joined(separator: " "), output: "Unexpected command")
            }
            let destinationURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            try Self.copyDirectoryContents(from: repoFixtureRoot, to: destinationURL)
            return ""
        }

        let service = ModInstallService(processRunner: processRunner)
        let sourceURL = "https://github.com/acme/mod-pack/tree/feature/release/mods/personal-notes"
        let result = try service.install(source: sourceURL, destinationRootURL: destinationRoot)

        XCTAssertEqual(result.definition.manifest.id, "acme.personal-notes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.installedDirectoryPath))
    }

    func testInstallServiceRejectsGitHubBlobURLWithGuidance() throws {
        let service = ModInstallService()
        let sourceURL = "https://github.com/acme/mod-pack/blob/main/mods/personal-notes/ui.mod.json"

        XCTAssertThrowsError(try service.preview(source: sourceURL)) { error in
            guard let installError = error as? ModInstallServiceError else {
                return XCTFail("Unexpected error: \(error)")
            }
            guard case .unsupportedGitHubBlobURL = installError else {
                return XCTFail("Expected unsupportedGitHubBlobURL, got \(installError)")
            }
            XCTAssertTrue(installError.localizedDescription.contains("/tree/"))
        }
    }

    func testInstallServiceRejectsAmbiguousPackageRoot() throws {
        let sourceRoot = try makeTempDirectory(prefix: "codexmods-ambiguous-src")
        let destinationRoot = try makeTempDirectory(prefix: "codexmods-ambiguous-dst")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: destinationRoot)
        }

        let first = sourceRoot.appendingPathComponent("first", isDirectory: true)
        let second = sourceRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let firstDefinition = try writeUIMod(
            to: first,
            id: "acme.first",
            name: "First",
            version: "1.0.0",
            permissions: .init(projectRead: true)
        )
        let secondDefinition = try writeUIMod(
            to: second,
            id: "acme.second",
            name: "Second",
            version: "1.0.0",
            permissions: .init(projectRead: true)
        )
        try writePackageManifest(
            to: first,
            ModPackageManifest(
                id: firstDefinition.manifest.id,
                name: firstDefinition.manifest.name,
                version: firstDefinition.manifest.version,
                permissions: [.projectRead]
            )
        )
        try writePackageManifest(
            to: second,
            ModPackageManifest(
                id: secondDefinition.manifest.id,
                name: secondDefinition.manifest.name,
                version: secondDefinition.manifest.version,
                permissions: [.projectRead]
            )
        )

        let service = ModInstallService()
        XCTAssertThrowsError(try service.install(source: sourceRoot.path, destinationRootURL: destinationRoot)) { error in
            guard let installError = error as? ModInstallServiceError else {
                return XCTFail("Unexpected error: \(error)")
            }
            guard case .packageRootNotFound = installError else {
                return XCTFail("Expected packageRootNotFound, got \(installError)")
            }
        }
    }

    func testInstallServiceUpdateRollsBackWhenCopyFails() throws {
        let sourceRoot = try makeTempDirectory(prefix: "codexmods-update-src")
        let existingRoot = try makeTempDirectory(prefix: "codexmods-update-existing")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: existingRoot)
        }

        let definition = try writeUIMod(
            to: sourceRoot,
            id: "acme.rollback",
            name: "Rollback Mod",
            version: "1.0.1",
            permissions: .init(projectRead: true)
        )
        let checksum = try checksumForUIMod(at: sourceRoot)
        try writePackageManifest(
            to: sourceRoot,
            ModPackageManifest(
                id: definition.manifest.id,
                name: definition.manifest.name,
                version: definition.manifest.version,
                permissions: [.projectRead],
                integrity: .init(uiModSha256: checksum)
            )
        )

        let existingInstallURL = existingRoot.appendingPathComponent("acme.rollback", isDirectory: true)
        try FileManager.default.createDirectory(at: existingInstallURL, withIntermediateDirectories: true)
        try Data("old-state".utf8).write(
            to: existingInstallURL.appendingPathComponent("marker.txt", isDirectory: false),
            options: [.atomic]
        )

        let failingFileManager = FailingCopyFileManager(
            failDestinationPath: existingInstallURL.standardizedFileURL.path
        )
        let service = ModInstallService(fileManager: failingFileManager)

        XCTAssertThrowsError(try service.update(source: sourceRoot.path, existingInstallURL: existingInstallURL))

        let markerURL = existingInstallURL.appendingPathComponent("marker.txt", isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path), "Expected existing install to be restored after rollback")
    }

    func testDiscoveryRejectsLegacySchemaVersionWithMigrationGuidance() throws {
        let root = try makeTempDirectory(prefix: "codexmods-legacy-schema")
        defer { try? FileManager.default.removeItem(at: root) }

        let modFolder = root.appendingPathComponent("legacy-v2", isDirectory: true)
        try FileManager.default.createDirectory(at: modFolder, withIntermediateDirectories: true)
        let legacyJSON = """
        {
          "schemaVersion": 2,
          "manifest": { "id": "acme.legacy", "name": "Legacy", "version": "1.0.0" },
          "theme": {}
        }
        """
        try Data(legacyJSON.utf8).write(to: modFolder.appendingPathComponent("ui.mod.json", isDirectory: false), options: [.atomic])

        let service = UIModDiscoveryService()
        XCTAssertThrowsError(try service.discoverMods(in: root.path, scope: .global)) { error in
            guard case let UIModDiscoveryError.invalidSchemaVersion(version) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(version, 2)
            XCTAssertTrue(error.localizedDescription.contains("schemaVersion 1"))
        }
    }

    func testDiscoveryRejectsLegacyRightInspectorKeyWithGuidance() throws {
        let root = try makeTempDirectory(prefix: "codexmods-legacy-slot")
        defer { try? FileManager.default.removeItem(at: root) }

        let modFolder = root.appendingPathComponent("legacy-slot", isDirectory: true)
        try FileManager.default.createDirectory(at: modFolder, withIntermediateDirectories: true)
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "manifest": { "id": "acme.legacy-slot", "name": "Legacy Slot", "version": "1.0.0" },
          "theme": {},
          "uiSlots": {
            "rightInspector": {
              "enabled": true
            }
          }
        }
        """
        try Data(legacyJSON.utf8).write(to: modFolder.appendingPathComponent("ui.mod.json", isDirectory: false), options: [.atomic])

        let service = UIModDiscoveryService()
        XCTAssertThrowsError(try service.discoverMods(in: root.path, scope: .global)) { error in
            guard case let UIModDiscoveryError.unsupportedLegacyKey(key) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(key, "uiSlots.rightInspector")
            XCTAssertTrue(error.localizedDescription.contains("uiSlots.modsBar"))
        }
    }

    func testDiscoveryAcceptsModsBarSlotInSchemaVersionOne() throws {
        let root = try makeTempDirectory(prefix: "codexmods-modsbar")
        defer { try? FileManager.default.removeItem(at: root) }

        let modFolder = root.appendingPathComponent("mods-bar", isDirectory: true)
        try FileManager.default.createDirectory(at: modFolder, withIntermediateDirectories: true)
        let json = """
        {
          "schemaVersion": 1,
          "manifest": { "id": "acme.modsbar", "name": "Mods Bar", "version": "1.0.0" },
          "theme": {},
          "uiSlots": {
            "modsBar": {
              "enabled": true,
              "title": "Summary"
            }
          }
        }
        """
        try Data(json.utf8).write(
            to: modFolder.appendingPathComponent("ui.mod.json", isDirectory: false),
            options: [.atomic]
        )

        let service = UIModDiscoveryService()
        let discovered = try service.discoverMods(in: root.path, scope: .global)
        XCTAssertEqual(discovered.count, 1)
        XCTAssertEqual(discovered.first?.definition.uiSlots?.modsBar?.enabled, true)
        XCTAssertEqual(discovered.first?.definition.uiSlots?.modsBar?.title, "Summary")
    }

    func testInstallServiceResolvesSingleNestedModFolder() throws {
        let sourceRoot = try makeTempDirectory(prefix: "codexmods-nested-src")
        let destinationRoot = try makeTempDirectory(prefix: "codexmods-nested-dst")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: destinationRoot)
        }

        let nested = sourceRoot
            .appendingPathComponent("thread-summary", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let definition = try writeUIMod(
            to: nested,
            id: "acme.nested",
            name: "Nested Mod",
            version: "1.0.0",
            permissions: .init(projectRead: true)
        )
        let checksum = try checksumForUIMod(at: nested)
        try writePackageManifest(
            to: nested,
            ModPackageManifest(
                id: definition.manifest.id,
                name: definition.manifest.name,
                version: definition.manifest.version,
                permissions: [.projectRead],
                integrity: .init(uiModSha256: checksum)
            )
        )

        let service = ModInstallService()
        let result = try service.install(source: sourceRoot.path, destinationRootURL: destinationRoot)

        XCTAssertEqual(result.definition.manifest.id, "acme.nested")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.installedDirectoryPath))
    }

    func testWriteSampleModIncludesPackageManifestAndScripts() throws {
        let root = try makeTempDirectory(prefix: "codexmods-sample")
        defer { try? FileManager.default.removeItem(at: root) }

        let discovery = UIModDiscoveryService()
        let definitionURL = try discovery.writeSampleMod(to: root.path, name: "thread-summary-sample")
        let modDirectory = definitionURL.deletingLastPathComponent()

        let manifestURL = modDirectory.appendingPathComponent("codex.mod.json", isDirectory: false)
        let hookScriptURL = modDirectory.appendingPathComponent("scripts/hook.sh", isDirectory: false)
        let automationScriptURL = modDirectory.appendingPathComponent("scripts/automation.sh", isDirectory: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: hookScriptURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: automationScriptURL.path))

        let hookAttributes = try FileManager.default.attributesOfItem(atPath: hookScriptURL.path)
        let hookPermissions = (hookAttributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(hookPermissions, 0o755)

        let resolved = try ModPackageManifestLoader.load(packageRootURL: modDirectory)
        XCTAssertEqual(resolved.manifestSource, .codexManifest)
        XCTAssertTrue(resolved.requestedPermissions.contains(.projectRead))
        XCTAssertNil(resolved.manifest.integrity?.uiModSha256)
    }

    func testDefaultProcessRunnerTimesOutWhenConfigured() throws {
        try withEnvironment("CODEX_PROCESS_TIMEOUT_MS", "100") {
            XCTAssertThrowsError(
                try ModInstallService.defaultProcessRunner(
                    ["sh", "-c", "sleep 1"],
                    nil
                )
            ) { error in
                guard case let ModInstallServiceError.commandFailed(_, output) = error else {
                    return XCTFail("Expected commandFailed, got \(error)")
                }
                XCTAssertTrue(output.contains("Timed out"))
            }
        }
    }

    func testDefaultProcessRunnerTruncatesOutputWhenConfigured() throws {
        try withEnvironment("CODEX_PROCESS_MAX_OUTPUT_BYTES", "1024") {
            let output = try ModInstallService.defaultProcessRunner(
                ["perl", "-e", "print 'x' x 5000"],
                nil
            )

            XCTAssertTrue(output.contains("[output truncated after 1024 bytes]"))
        }
    }

    private func withEnvironment(
        _ key: String,
        _ value: String,
        body: () throws -> Void
    ) rethrows {
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, value, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        try body()
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeUIMod(
        to root: URL,
        id: String,
        name: String,
        version: String,
        permissions: ModExtensionPermissions
    ) throws -> UIModDefinition {
        let definition = UIModDefinition(
            schemaVersion: 1,
            manifest: UIModManifest(id: id, name: name, version: version),
            theme: ModThemeOverride(),
            hooks: [
                ModHookDefinition(
                    id: "turn-summary",
                    event: .turnCompleted,
                    handler: ModExtensionHandler(command: ["sh", "scripts/hook.sh"], cwd: "."),
                    permissions: permissions,
                    timeoutMs: 8000,
                    debounceMs: 0
                ),
            ]
        )

        let data = try JSONEncoder().encode(definition)
        try data.write(to: root.appendingPathComponent("ui.mod.json", isDirectory: false), options: [.atomic])
        return definition
    }

    private func writePackageManifest(to root: URL, _ manifest: ModPackageManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: root.appendingPathComponent("codex.mod.json", isDirectory: false), options: [.atomic])
    }

    private func checksumForUIMod(at root: URL) throws -> String {
        let data = try Data(contentsOf: root.appendingPathComponent("ui.mod.json", isDirectory: false))
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    private static func copyDirectoryContents(from source: URL, to destination: URL) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                let target = destination.appendingPathComponent(entry.lastPathComponent, isDirectory: true)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                try Self.copyDirectoryContents(from: entry, to: target)
            } else {
                let target = destination.appendingPathComponent(entry.lastPathComponent, isDirectory: false)
                try FileManager.default.copyItem(at: entry, to: target)
            }
        }
    }
}

private final class FailingCopyFileManager: FileManager {
    private let failDestinationPath: String

    init(failDestinationPath: String) {
        self.failDestinationPath = failDestinationPath
        super.init()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if dstURL.standardizedFileURL.path == failDestinationPath {
            throw NSError(
                domain: "CodexModsTests.FailingCopyFileManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Injected copy failure for rollback test"]
            )
        }
        try super.copyItem(at: srcURL, to: dstURL)
    }
}
