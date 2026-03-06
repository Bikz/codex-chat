import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import CodexExtensions
import CodexMods
import Foundation
import XCTest

@MainActor
final class ExtensionPermissionIsolationTests: XCTestCase {
    func testRunHooksIsolatesPermissionDecisionsByInstallID() async throws {
        let rootURL = try makeTempDirectory(prefix: "extension-permission-isolation")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let database = try MetadataDatabase(
            databaseURL: rootURL.appendingPathComponent("metadata.sqlite", isDirectory: false)
        )
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        let project = try await repositories.projectRepository.createProject(
            named: "Permissions",
            path: rootURL.appendingPathComponent("project", isDirectory: true).path,
            trustState: .trusted,
            isGeneralProject: false
        )
        model.projectsState = .loaded([project])

        let grantedDirectory = rootURL.appendingPathComponent("granted-mod", isDirectory: true)
        let deniedDirectory = rootURL.appendingPathComponent("denied-mod", isDirectory: true)
        try FileManager.default.createDirectory(at: grantedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deniedDirectory, withIntermediateDirectories: true)

        let grantedMarkerURL = grantedDirectory.appendingPathComponent("granted.marker", isDirectory: false)
        let deniedMarkerURL = deniedDirectory.appendingPathComponent("denied.marker", isDirectory: false)
        let grantedScriptURL = try makeWorkerScript(
            directory: grantedDirectory,
            markerURL: grantedMarkerURL
        )
        let deniedScriptURL = try makeWorkerScript(
            directory: deniedDirectory,
            markerURL: deniedMarkerURL
        )

        let modID = "acme.shared-mod"
        let globalInstallID = AppModel.syntheticExtensionInstallID(
            scope: .global,
            projectID: nil,
            modID: modID
        )
        let projectInstallID = AppModel.syntheticExtensionInstallID(
            scope: .project,
            projectID: project.id,
            modID: modID
        )

        try await repositories.extensionPermissionRepository.set(
            installID: globalInstallID,
            modID: modID,
            permissionKey: .projectWrite,
            status: .granted,
            grantedAt: Date()
        )
        try await repositories.extensionPermissionRepository.set(
            installID: projectInstallID,
            modID: modID,
            permissionKey: .projectWrite,
            status: .denied,
            grantedAt: Date()
        )

        model.activeExtensionHooks = [
            AppModel.ResolvedExtensionHook(
                modID: modID,
                modDirectoryPath: grantedDirectory.path,
                definition: ModHookDefinition(
                    id: "global-hook",
                    event: .turnCompleted,
                    handler: ModExtensionHandler(command: [grantedScriptURL.path]),
                    permissions: .init(projectWrite: true)
                ),
                installID: globalInstallID,
                installScope: .global
            ),
            AppModel.ResolvedExtensionHook(
                modID: modID,
                modDirectoryPath: deniedDirectory.path,
                definition: ModHookDefinition(
                    id: "project-hook",
                    event: .turnCompleted,
                    handler: ModExtensionHandler(command: [deniedScriptURL.path]),
                    permissions: .init(projectWrite: true)
                ),
                installID: projectInstallID,
                installScope: .project,
                installProjectID: project.id
            ),
        ]

        await model.runHooks(
            for: ExtensionEventEnvelope(
                event: .turnCompleted,
                timestamp: Date(),
                project: .init(id: project.id.uuidString, path: project.path),
                thread: .init(id: UUID().uuidString)
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: grantedMarkerURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: deniedMarkerURL.path))
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeWorkerScript(directory: URL, markerURL: URL) throws -> URL {
        let scriptURL = directory.appendingPathComponent("hook.sh", isDirectory: false)
        let script = """
        #!/bin/sh
        touch "\(markerURL.path)"
        echo '{"ok":true}'
        """
        try Data(script.utf8).write(to: scriptURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }
}
