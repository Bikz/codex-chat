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

    func testPerformModsBarActionNativeActionReportsUnsupportedAction() async throws {
        let repositories = try makeRepositories(prefix: "modsbar-native-action")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        let projectID = UUID()
        let threadID = UUID()
        let projectPath = try makeTempDirectory(prefix: "modsbar-native-project").path

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
        model.selectedThreadID = threadID

        model.performModsBarAction(
            .init(
                id: "native",
                label: "Native",
                kind: .nativeAction,
                payload: ["actionID": "unknown.action"]
            )
        )

        try await eventually(timeoutSeconds: 10) {
            model.extensionStatusMessage?.contains("Native action failed:") == true
        }

        XCTAssertTrue(model.extensionStatusMessage?.contains("Unknown computer action: unknown.action") == true)
    }

    func testUpsertPersonalNotesInlineEmitsModsBarAction() async throws {
        let repositories = try makeRepositories(prefix: "modsbar-personal-notes-upsert")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        let projectID = UUID()
        let threadID = UUID()
        let projectPath = try makeTempDirectory(prefix: "modsbar-personal-notes-upsert-project").path
        let output = URL(fileURLWithPath: projectPath).appendingPathComponent("notes-upsert.json", isDirectory: false)
        let script = try makeCaptureScript(outputURL: output)

        model.projectsState = .loaded([
            ProjectRecord(id: projectID, name: "Project", path: projectPath, trustState: .trusted),
        ])
        model.selectedProjectID = projectID
        model.threadsState = .loaded([
            ThreadRecord(id: threadID, projectId: projectID, title: "Thread"),
        ])
        model.selectedThreadID = threadID
        model.activeModsBarModID = "codexchat.personal-notes"
        model.activeModsBarSlot = .init(enabled: true, title: "Personal Notes")
        model.activeExtensionHooks = [
            AppModel.ResolvedExtensionHook(
                modID: "codexchat.personal-notes",
                modDirectoryPath: projectPath,
                definition: ModHookDefinition(
                    id: "notes-action",
                    event: .modsBarAction,
                    handler: .init(command: [script.path], cwd: ".")
                )
            ),
        ]

        model.upsertPersonalNotesInline("Remember to ship after make quick.")

        try await eventually(timeoutSeconds: 10) {
            FileManager.default.fileExists(atPath: output.path)
        }

        let written = try String(contentsOf: output)
        XCTAssertTrue(written.contains("\"event\":\"modsBar.action\""))
        XCTAssertTrue(written.contains("\"operation\":\"upsert\""))
        XCTAssertTrue(written.contains("\"targetHookID\":\"notes-action\""))
        XCTAssertTrue(written.contains("\"targetModID\":\"codexchat.personal-notes\""))
        XCTAssertTrue(written.contains("\"input\":\"Remember to ship after make quick.\""))
    }

    func testUpsertPersonalNotesInlineClearsWhenTextIsEmpty() async throws {
        let repositories = try makeRepositories(prefix: "modsbar-personal-notes-clear")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        let projectID = UUID()
        let threadID = UUID()
        let projectPath = try makeTempDirectory(prefix: "modsbar-personal-notes-clear-project").path
        let output = URL(fileURLWithPath: projectPath).appendingPathComponent("notes-clear.json", isDirectory: false)
        let script = try makeCaptureScript(outputURL: output)

        model.projectsState = .loaded([
            ProjectRecord(id: projectID, name: "Project", path: projectPath, trustState: .trusted),
        ])
        model.selectedProjectID = projectID
        model.threadsState = .loaded([
            ThreadRecord(id: threadID, projectId: projectID, title: "Thread"),
        ])
        model.selectedThreadID = threadID
        model.activeModsBarModID = "codexchat.personal-notes"
        model.activeModsBarSlot = .init(enabled: true, title: "Personal Notes")
        model.activeExtensionHooks = [
            AppModel.ResolvedExtensionHook(
                modID: "codexchat.personal-notes",
                modDirectoryPath: projectPath,
                definition: ModHookDefinition(
                    id: "notes-action",
                    event: .modsBarAction,
                    handler: .init(command: [script.path], cwd: ".")
                )
            ),
        ]

        model.upsertPersonalNotesInline("   ")

        try await eventually(timeoutSeconds: 10) {
            FileManager.default.fileExists(atPath: output.path)
        }

        let written = try String(contentsOf: output)
        XCTAssertTrue(written.contains("\"event\":\"modsBar.action\""))
        XCTAssertTrue(written.contains("\"operation\":\"clear\""))
        XCTAssertTrue(written.contains("\"targetHookID\":\"notes-action\""))
        XCTAssertFalse(written.contains("\"input\""))
    }

    func testPromptBookEntriesFromStateReturnsDefaultsWhenMissingStateFile() throws {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let modRoot = try makeTempDirectory(prefix: "modsbar-promptbook-defaults")

        model.selectedThreadID = UUID()
        model.activeModsBarModID = "codexchat.prompt-book"
        model.activeModsBarSlot = .init(enabled: true, title: "Prompt Book")
        model.activeModsBarModDirectoryPath = modRoot.path

        let entries = model.promptBookEntriesFromState()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].title, "Ship Checklist")
        XCTAssertEqual(entries[1].title, "Risk Scan")
    }

    func testPromptBookEntriesFromStateReadsSavedPromptBodies() throws {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let modRoot = try makeTempDirectory(prefix: "modsbar-promptbook-state")
        let stateDirectory = modRoot.appendingPathComponent(".codexchat/state", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let stateFile = stateDirectory.appendingPathComponent("prompt-book.json", isDirectory: false)

        let payload = """
        {
          "prompts": [
            {
              "id": "deep-review",
              "title": "Deep Review",
              "text": "Perform a deep architectural review, include reliability, edge-case handling, and migration strategy notes."
            }
          ]
        }
        """
        try payload.write(to: stateFile, atomically: true, encoding: .utf8)

        model.selectedThreadID = UUID()
        model.activeModsBarModID = "codexchat.prompt-book"
        model.activeModsBarSlot = .init(enabled: true, title: "Prompt Book")
        model.activeModsBarModDirectoryPath = modRoot.path

        let entries = model.promptBookEntriesFromState()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].title, "Deep Review")
        XCTAssertEqual(
            entries[0].text,
            "Perform a deep architectural review, include reliability, edge-case handling, and migration strategy notes."
        )
    }

    func testModsBarQuickSwitchOptionsIncludeProjectAndGlobalChoices() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let projectMod = makeModsBarMod(id: "acme.project", name: "Project Prompt Book", scope: .project, directorySuffix: "project")
        let globalMod = makeModsBarMod(id: "acme.global", name: "Global Notes", scope: .global, directorySuffix: "global")

        model.modsState = .loaded(
            AppModel.ModsSurfaceModel(
                globalMods: [globalMod],
                projectMods: [projectMod],
                selectedGlobalModPath: globalMod.directoryPath,
                selectedProjectModPath: nil
            )
        )

        let options = model.modsBarQuickSwitchOptions
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options[0].scope, .project)
        XCTAssertEqual(options[1].scope, .global)
        XCTAssertTrue(options[1].isSelected)
        XCTAssertTrue(model.hasModsBarQuickSwitchChoices)
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeModsBarMod(id: String, name: String, scope: ModScope, directorySuffix: String) -> DiscoveredUIMod {
        DiscoveredUIMod(
            scope: scope,
            directoryPath: "/tmp/\(directorySuffix)-\(UUID().uuidString)",
            definitionPath: "/tmp/\(directorySuffix)-ui.mod.json",
            definition: UIModDefinition(
                manifest: .init(id: id, name: name, version: "1.0.0"),
                theme: .init(),
                uiSlots: .init(modsBar: .init(enabled: true, title: name))
            ),
            computedChecksum: nil
        )
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
