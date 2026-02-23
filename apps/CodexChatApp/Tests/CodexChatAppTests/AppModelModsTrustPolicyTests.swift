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

    private func makeMod(id: String, directoryPath: String) -> DiscoveredUIMod {
        DiscoveredUIMod(
            scope: .project,
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
