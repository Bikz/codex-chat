import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import CodexExtensions
import CodexMods
import Foundation
import XCTest

@MainActor
final class ModsBarActionTests: XCTestCase {
    func testSelectedExtensionModsBarStateFallsBackToGlobalState() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let globalState = AppModel.ExtensionModsBarState(
            title: "Prompt Book",
            markdown: "- ship checklist",
            scope: .global,
            actions: [],
            updatedAt: Date()
        )
        model.extensionGlobalModsBarState = globalState

        XCTAssertEqual(model.selectedExtensionModsBarState?.scope, .global)
        XCTAssertEqual(model.selectedExtensionModsBarState?.title, "Prompt Book")
    }

    func testPerformModsBarActionComposerInsertAppendsToComposer() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.composerText = "Existing text"

        model.performModsBarAction(
            .init(
                id: "insert",
                label: "Insert",
                kind: .composerInsert,
                payload: ["text": "Added from action"]
            )
        )

        XCTAssertEqual(model.composerText, "Existing text\n\nAdded from action")
    }

    func testPerformModsBarActionRoutesModsBarActionEventToTargetMod() async throws {
        let repositories = try makeRepositories(prefix: "modsbar-action-repositories")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        let projectID = UUID()
        let threadID = UUID()
        let projectPath = try makeTempDirectory(prefix: "modsbar-action-project").path
        let targetOutput = URL(fileURLWithPath: projectPath).appendingPathComponent("target.json", isDirectory: false)
        let otherOutput = URL(fileURLWithPath: projectPath).appendingPathComponent("other.json", isDirectory: false)

        model.projectsState = .loaded([
            ProjectRecord(name: "Project", path: projectPath, trustState: .trusted),
        ])
        model.selectedProjectID = model.projects.first?.id
        model.selectedThreadID = threadID

        let targetScript = try makeCaptureScript(outputURL: targetOutput)
        let otherScript = try makeCaptureScript(outputURL: otherOutput)

        model.activeExtensionHooks = [
            AppModel.ResolvedExtensionHook(
                modID: "acme.target",
                modDirectoryPath: projectPath,
                definition: ModHookDefinition(
                    id: "target-hook",
                    event: .modsBarAction,
                    handler: .init(command: [targetScript.path], cwd: ".")
                )
            ),
            AppModel.ResolvedExtensionHook(
                modID: "acme.other",
                modDirectoryPath: projectPath,
                definition: ModHookDefinition(
                    id: "other-hook",
                    event: .modsBarAction,
                    handler: .init(command: [otherScript.path], cwd: ".")
                )
            ),
        ]

        model.activeModsBarModID = "acme.target"
        model.projectsState = .loaded([
            ProjectRecord(
                id: projectID,
                name: "Project",
                path: projectPath,
                trustState: .trusted
            ),
        ])
        model.selectedProjectID = projectID
        model.threadsState = .loaded([
            ThreadRecord(id: threadID, projectId: projectID, title: "Thread"),
        ])

        model.performModsBarAction(
            .init(
                id: "emit",
                label: "Emit",
                kind: .emitEvent,
                payload: [
                    "targetHookID": "target-hook",
                ]
            )
        )

        try await eventually(timeoutSeconds: 10) {
            FileManager.default.fileExists(atPath: targetOutput.path)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: targetOutput.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: otherOutput.path))

        let written = try String(contentsOf: targetOutput)
        XCTAssertTrue(written.contains("\"event\":\"modsBar.action\""))
        XCTAssertTrue(written.contains("\"targetHookID\":\"target-hook\""))
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRepositories(prefix: String) throws -> MetadataRepositories {
        let root = try makeTempDirectory(prefix: prefix)
        let database = try MetadataDatabase(databaseURL: root.appendingPathComponent("metadata.sqlite", isDirectory: false))
        return MetadataRepositories(database: database)
    }

    private func makeCaptureScript(outputURL: URL) throws -> URL {
        let scriptURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("capture-\(UUID().uuidString).sh", isDirectory: false)
        let script = """
        #!/bin/sh
        cat > "\(outputURL.path)"
        echo '{"ok":true}'
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
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
