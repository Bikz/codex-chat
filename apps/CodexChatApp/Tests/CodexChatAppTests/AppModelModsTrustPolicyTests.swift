import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import CodexMods
import XCTest

@MainActor
final class AppModelModsTrustPolicyTests: XCTestCase {
    func testBlockedCapabilitiesForProjectInstallInUntrustedProjectIncludeFilesystemAndNetworkForRemoteSource() {
        let model = makeModelWithSelectedProject(trustState: .untrusted)

        let blocked = model.blockedCapabilitiesForModInstall(
            source: "https://github.com/acme/mod-pack",
            scope: .project
        )

        XCTAssertEqual(blocked, Set([.filesystemWrite, .network]))
    }

    func testBlockedCapabilitiesForGlobalInstallIgnoreProjectTrustGate() {
        let model = makeModelWithSelectedProject(trustState: .untrusted)

        let blocked = model.blockedCapabilitiesForModInstall(
            source: "https://github.com/acme/mod-pack",
            scope: .global
        )

        XCTAssertTrue(blocked.isEmpty)
    }

    func testInstallModSetsBlockedStatusAndSkipsOperationForUntrustedRemoteSource() {
        let model = makeModelWithSelectedProject(trustState: .untrusted)

        model.installMod(
            source: "https://github.com/acme/mod-pack",
            scope: .project
        )

        XCTAssertEqual(
            model.modStatusMessage,
            "Mod install blocked in untrusted project: filesystem-write, network."
        )
        XCTAssertFalse(model.isModOperationInProgress)
    }

    func testUpdateModSetsBlockedStatusForUntrustedRemoteSource() async throws {
        let repositories = try makeRepositories(prefix: "mods-trust-update")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        let projectURL = try makeTempDirectory(prefix: "mods-trust-update-project")
        let project = try await repositories.projectRepository.createProject(
            named: "Project",
            path: projectURL.path,
            trustState: .untrusted,
            isGeneralProject: false
        )

        model.projectsState = .loaded([project])
        model.selectedProjectID = project.id

        let modID = "acme.remote-mod"
        _ = try await repositories.extensionInstallRepository.upsert(
            ExtensionInstallRecord(
                id: "project:\(project.id.uuidString):\(modID)",
                modID: modID,
                scope: .project,
                projectID: project.id,
                sourceURL: "https://github.com/acme/remote-mod",
                installedPath: projectURL.appendingPathComponent("mods/remote-mod", isDirectory: true).path,
                enabled: true
            )
        )

        model.updateInstalledMod(
            makeMod(id: modID, directoryPath: projectURL.path),
            scope: .project
        )

        try await eventually(timeoutSeconds: 3) {
            model.modStatusMessage?.contains("Mod update blocked in untrusted project") == true
                && model.isModOperationInProgress == false
        }
    }

    func testSetGlobalModDoesNotDisableOtherEnabledGlobalInstalls() async throws {
        let repositories = try makeRepositories(prefix: "mods-global-enable")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        let modAID = "acme.prompt-book"
        let modBID = "acme.personal-notes"
        let modBPath = "/tmp/mod-b-\(UUID().uuidString)"

        _ = try await repositories.extensionInstallRepository.upsert(
            ExtensionInstallRecord(
                id: "global:\(modAID)",
                modID: modAID,
                scope: .global,
                projectID: nil,
                sourceURL: "https://github.com/acme/prompt-book",
                installedPath: "/tmp/mod-a-\(UUID().uuidString)",
                enabled: true
            )
        )
        _ = try await repositories.extensionInstallRepository.upsert(
            ExtensionInstallRecord(
                id: "global:\(modBID)",
                modID: modBID,
                scope: .global,
                projectID: nil,
                sourceURL: "https://github.com/acme/personal-notes",
                installedPath: modBPath,
                enabled: false
            )
        )

        model.setGlobalMod(makeMod(id: modBID, directoryPath: modBPath, scope: .global))

        let deadline = Date().addingTimeInterval(3)
        var conditionMet = false
        while Date() < deadline {
            let globalPath = try await repositories.preferenceRepository.getPreference(key: .globalUIModPath)
            let installs = try await repositories.extensionInstallRepository.list()
            let aEnabled = installs.first(where: { $0.modID == modAID })?.enabled
            let bEnabled = installs.first(where: { $0.modID == modBID })?.enabled
            if globalPath == modBPath, aEnabled == true, bEnabled == true {
                conditionMet = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            await Task.yield()
        }
        XCTAssertTrue(conditionMet)
    }

    func testSetInstalledModEnabledOffClearsActiveGlobalSelection() async throws {
        let repositories = try makeRepositories(prefix: "mods-global-disable")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        let modID = "acme.prompt-book"
        let modPath = "/tmp/mod-\(UUID().uuidString)"

        _ = try await repositories.extensionInstallRepository.upsert(
            ExtensionInstallRecord(
                id: "global:\(modID)",
                modID: modID,
                scope: .global,
                projectID: nil,
                sourceURL: "https://github.com/acme/prompt-book",
                installedPath: modPath,
                enabled: true
            )
        )
        try await repositories.preferenceRepository.setPreference(key: .globalUIModPath, value: modPath)

        model.modsState = .loaded(
            AppModel.ModsSurfaceModel(
                globalMods: [],
                projectMods: [],
                selectedGlobalModPath: modPath,
                selectedProjectModPath: nil,
                enabledGlobalModIDs: [modID],
                enabledProjectModIDs: []
            )
        )

        model.setInstalledModEnabled(
            makeMod(id: modID, directoryPath: modPath, scope: .global),
            scope: .global,
            enabled: false
        )

        let deadline = Date().addingTimeInterval(3)
        var conditionMet = false
        while Date() < deadline {
            let path = try await repositories.preferenceRepository.getPreference(key: .globalUIModPath)
            let installs = try await repositories.extensionInstallRepository.list()
            let enabled = installs.first(where: { $0.modID == modID })?.enabled
            if (path ?? "").isEmpty, enabled == false {
                conditionMet = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            await Task.yield()
        }
        XCTAssertTrue(conditionMet)
    }

    func testResolveEnabledModIDsHandlesDuplicateManifestIDsInSameScope() {
        let duplicateID = "acme.prompt-book"
        let selectedProjectID = UUID()
        let globalMods = [
            makeMod(id: duplicateID, directoryPath: "/tmp/mod-a", scope: .global),
            makeMod(id: duplicateID, directoryPath: "/tmp/mod-b", scope: .global),
        ]

        let resolved = AppModel.resolveEnabledModIDs(
            globalMods: globalMods,
            projectMods: [],
            selectedGlobalPath: nil,
            selectedProjectPath: nil,
            selectedProjectID: selectedProjectID,
            installRecords: [
                ExtensionInstallRecord(
                    id: "global:\(duplicateID)",
                    modID: duplicateID,
                    scope: .global,
                    projectID: nil,
                    sourceURL: "https://github.com/acme/prompt-book",
                    installedPath: "/tmp/mod-a",
                    enabled: true
                ),
            ]
        )

        XCTAssertEqual(resolved.global, [duplicateID])
        XCTAssertTrue(resolved.project.isEmpty)
    }

    private func makeModelWithSelectedProject(trustState: ProjectTrustState) -> AppModel {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let projectID = UUID()
        model.projectsState = .loaded([
            ProjectRecord(
                id: projectID,
                name: "Project",
                path: "/tmp/project-\(projectID.uuidString)",
                trustState: trustState
            ),
        ])
        model.selectedProjectID = projectID
        return model
    }

    private func makeMod(id: String, directoryPath: String, scope: ModScope = .project) -> DiscoveredUIMod {
        DiscoveredUIMod(
            scope: scope,
            directoryPath: directoryPath,
            definitionPath: "\(directoryPath)/ui.mod.json",
            definition: UIModDefinition(
                manifest: .init(id: id, name: "Remote Mod", version: "1.0.0"),
                theme: .init()
            ),
            computedChecksum: nil
        )
    }

    private func makeRepositories(prefix: String) throws -> MetadataRepositories {
        let root = try makeTempDirectory(prefix: prefix)
        let database = try MetadataDatabase(
            databaseURL: root.appendingPathComponent("metadata.sqlite", isDirectory: false)
        )
        return MetadataRepositories(database: database)
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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
