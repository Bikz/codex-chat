import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import CodexMods
import XCTest

@MainActor
final class AppModelAdvancedExecutableModsTests: XCTestCase {
    func testRestoreAdvancedExecutableModsUnlockDefaultsToLockedForNewInstall() async throws {
        let repositories = try makeRepositories(prefix: "advanced-mods-new-user")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        await model.restoreAdvancedExecutableModsUnlockIfNeeded()

        XCTAssertFalse(model.areAdvancedExecutableModsUnlocked)
        let unlockPreference = try await repositories.preferenceRepository.getPreference(key: .advancedExecutableModsUnlock)
        let migrationPreference = try await repositories.preferenceRepository.getPreference(key: .advancedExecutableModsMigrationV1)
        XCTAssertEqual(unlockPreference, "deny")
        XCTAssertEqual(migrationPreference, "1")
    }

    func testRestoreAdvancedExecutableModsUnlockPreservesLegacyBehaviorForExistingInstall() async throws {
        let repositories = try makeRepositories(prefix: "advanced-mods-existing-user")
        _ = try await repositories.extensionInstallRepository.upsert(
            ExtensionInstallRecord(
                id: "global:legacy.mod",
                modID: "legacy.mod",
                scope: .global,
                sourceURL: "https://github.com/example/legacy-mod",
                installedPath: "/tmp/legacy-mod",
                enabled: true
            )
        )

        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        await model.restoreAdvancedExecutableModsUnlockIfNeeded()

        XCTAssertTrue(model.areAdvancedExecutableModsUnlocked)
        let unlockPreference = try await repositories.preferenceRepository.getPreference(key: .advancedExecutableModsUnlock)
        let migrationPreference = try await repositories.preferenceRepository.getPreference(key: .advancedExecutableModsMigrationV1)
        XCTAssertEqual(unlockPreference, "allow")
        XCTAssertEqual(migrationPreference, "1")
    }

    func testExecutableModBlockedReasonForThirdPartyWhenLocked() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.areAdvancedExecutableModsUnlocked = false

        let mod = makeExecutableMod(
            id: "acme.third-party",
            name: "Third Party",
            directoryPath: "/tmp/acme-third-party"
        )

        XCTAssertFalse(model.canRunExecutableModFeatures(for: mod))
        XCTAssertNotNil(model.executableModBlockedReason(for: mod))
    }

    func testExecutableModAllowedForFirstPartyWhenLocked() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.areAdvancedExecutableModsUnlocked = false

        let mod = makeExecutableMod(
            id: "codexchat.personal-notes",
            name: "Personal Notes",
            directoryPath: "/tmp/codexchat-personal-notes"
        )

        XCTAssertTrue(model.canRunExecutableModFeatures(for: mod))
        XCTAssertNil(model.executableModBlockedReason(for: mod))
    }

    func testInstallModKeepsThirdPartyExecutableModDisabledWhenLocked() async throws {
        let repositories = try makeRepositories(prefix: "advanced-mods-install-lock")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        let projectRoot = try makeTempDirectory(prefix: "advanced-mods-project")
        let project = try await repositories.projectRepository.createProject(
            named: "Project",
            path: projectRoot.path,
            trustState: .trusted,
            isGeneralProject: false
        )

        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id
        model.areAdvancedExecutableModsUnlocked = false

        let sourceRoot = try makeTempDirectory(prefix: "advanced-mods-source")
        let definitionURL = try UIModDiscoveryService().writeSampleMod(
            to: sourceRoot.path,
            name: "acme-third-party"
        )

        model.installMod(
            source: definitionURL.deletingLastPathComponent().path,
            scope: .project
        )

        try await eventually(timeoutSeconds: 10) {
            model.isModOperationInProgress == false && model.modStatusMessage?.contains("disabled") == true
        }

        let installRecords = try await repositories.extensionInstallRepository.list()
        guard let install = installRecords.first(where: { record in
            record.scope == .project
                && record.projectID == project.id
                && record.modID == "acme-third-party"
        }) else {
            return XCTFail("Expected install record for acme-third-party")
        }

        XCTAssertFalse(install.enabled)
        XCTAssertTrue(model.modStatusMessage?.contains("disabled") == true)
    }

    func testSetInstalledModEnabledDoesNotEnableThirdPartyExecutableModWhenLocked() async throws {
        let repositories = try makeRepositories(prefix: "advanced-mods-toggle-lock")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        model.areAdvancedExecutableModsUnlocked = false

        let mod = makeExecutableMod(
            id: "acme.third-party",
            name: "Third Party",
            directoryPath: "/tmp/acme-third-party-\(UUID().uuidString)",
            scope: .global
        )

        _ = try await repositories.extensionInstallRepository.upsert(
            ExtensionInstallRecord(
                id: "global:\(mod.definition.manifest.id)",
                modID: mod.definition.manifest.id,
                scope: .global,
                sourceURL: mod.directoryPath,
                installedPath: mod.directoryPath,
                enabled: false
            )
        )

        model.setInstalledModEnabled(mod, scope: .global, enabled: true)

        XCTAssertEqual(model.modStatusMessage, model.executableModBlockedReason(for: mod))

        let installs = try await repositories.extensionInstallRepository.list()
        let record = try XCTUnwrap(installs.first(where: { $0.modID == mod.definition.manifest.id }))
        XCTAssertFalse(record.enabled)
    }

    func testUpdateInstalledModKeepsThirdPartyExecutableModDisabledWhenLocked() async throws {
        let repositories = try makeRepositories(prefix: "advanced-mods-update-lock")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        model.areAdvancedExecutableModsUnlocked = false

        let sourceRoot = try makeTempDirectory(prefix: "advanced-mods-update-source")
        let definitionURL = try UIModDiscoveryService().writeSampleMod(
            to: sourceRoot.path,
            name: "acme-third-party"
        )
        let sourceModURL = definitionURL.deletingLastPathComponent()
        let installedRoot = try makeTempDirectory(prefix: "advanced-mods-update-installed")
        let installedModURL = installedRoot.appendingPathComponent("acme-third-party", isDirectory: true)
        try FileManager.default.copyItem(at: sourceModURL, to: installedModURL)

        _ = try await repositories.extensionInstallRepository.upsert(
            ExtensionInstallRecord(
                id: "global:acme-third-party",
                modID: "acme-third-party",
                scope: .global,
                sourceURL: sourceModURL.path,
                installedPath: installedModURL.path,
                enabled: true
            )
        )

        model.updateInstalledMod(
            makeExecutableMod(
                id: "acme-third-party",
                name: "Third Party",
                directoryPath: installedModURL.path,
                scope: .global
            ),
            scope: .global
        )

        try await eventually(timeoutSeconds: 10) {
            model.isModOperationInProgress == false
                && model.modStatusMessage?.contains("but it is disabled") == true
        }

        let installs = try await repositories.extensionInstallRepository.list()
        let record = try XCTUnwrap(installs.first(where: { $0.modID == "acme-third-party" }))
        XCTAssertFalse(record.enabled)
    }

    func testUpdateInstalledModPreservesDisabledStateWhenRuntimeWasAlreadyOff() async throws {
        let repositories = try makeRepositories(prefix: "advanced-mods-update-disabled")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        model.areAdvancedExecutableModsUnlocked = true

        let sourceRoot = try makeTempDirectory(prefix: "advanced-mods-update-disabled-source")
        let definitionURL = try UIModDiscoveryService().writeSampleMod(
            to: sourceRoot.path,
            name: "acme-disabled"
        )
        let sourceModURL = definitionURL.deletingLastPathComponent()
        let installedRoot = try makeTempDirectory(prefix: "advanced-mods-update-disabled-installed")
        let installedModURL = installedRoot.appendingPathComponent("acme-disabled", isDirectory: true)
        try FileManager.default.copyItem(at: sourceModURL, to: installedModURL)

        _ = try await repositories.extensionInstallRepository.upsert(
            ExtensionInstallRecord(
                id: "global:acme-disabled",
                modID: "acme-disabled",
                scope: .global,
                sourceURL: sourceModURL.path,
                installedPath: installedModURL.path,
                enabled: false
            )
        )

        model.updateInstalledMod(
            makeExecutableMod(
                id: "acme-disabled",
                name: "Disabled",
                directoryPath: installedModURL.path,
                scope: .global
            ),
            scope: .global
        )

        try await eventually(timeoutSeconds: 10) {
            model.isModOperationInProgress == false
                && model.modStatusMessage == "Updated mod: acme-disabled. Runtime remains disabled."
        }

        let installs = try await repositories.extensionInstallRepository.list()
        let record = try XCTUnwrap(installs.first(where: { $0.modID == "acme-disabled" }))
        XCTAssertFalse(record.enabled)
    }

    private func makeExecutableMod(
        id: String,
        name: String,
        directoryPath: String,
        scope: ModScope = .project
    ) -> DiscoveredUIMod {
        DiscoveredUIMod(
            scope: scope,
            directoryPath: directoryPath,
            definitionPath: "\(directoryPath)/ui.mod.json",
            definition: UIModDefinition(
                manifest: .init(id: id, name: name, version: "1.0.0"),
                theme: .init(),
                hooks: [
                    .init(
                        id: "hook-1",
                        event: .turnCompleted,
                        handler: .init(command: ["/bin/echo", "ok"])
                    ),
                ]
            ),
            computedChecksum: nil
        )
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRepositories(prefix: String) throws -> MetadataRepositories {
        let root = try makeTempDirectory(prefix: prefix)
        let database = try MetadataDatabase(
            databaseURL: root.appendingPathComponent("metadata.sqlite", isDirectory: false)
        )
        return MetadataRepositories(database: database)
    }

    private func eventually(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            await Task.yield()
        }
        throw XCTestError(.failureWhileWaiting)
    }
}
