import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import CodexExtensions
import CodexMods
import Foundation
import XCTest

@MainActor
final class ExtensionAutomationExecutionContextTests: XCTestCase {
    func testExecuteAutomationUsesStoredExecutionContext() async throws {
        let rootURL = try makeTempDirectory(prefix: "extension-automation-context")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let database = try MetadataDatabase(
            databaseURL: rootURL.appendingPathComponent("metadata.sqlite", isDirectory: false)
        )
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        let targetProjectURL = rootURL.appendingPathComponent("target-project", isDirectory: true)
        let otherProjectURL = rootURL.appendingPathComponent("other-project", isDirectory: true)
        let modDirectoryURL = rootURL.appendingPathComponent("project-mod", isDirectory: true)
        try FileManager.default.createDirectory(at: targetProjectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherProjectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modDirectoryURL, withIntermediateDirectories: true)

        let targetProject = try await repositories.projectRepository.createProject(
            named: "Target",
            path: targetProjectURL.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let otherProject = try await repositories.projectRepository.createProject(
            named: "Other",
            path: otherProjectURL.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let selectedThread = try await repositories.threadRepository.createThread(
            projectID: otherProject.id,
            title: "Selected"
        )
        let executionThread = UUID()

        model.projectsState = .loaded([targetProject, otherProject])
        model.selectedProjectID = otherProject.id
        model.selectedThreadID = selectedThread.id

        let captureURL = modDirectoryURL.appendingPathComponent("automation-input.json", isDirectory: false)
        let scriptURL = try makeAutomationCaptureScript(
            directory: modDirectoryURL,
            captureURL: captureURL
        )
        let resolved = AppModel.ResolvedExtensionAutomation(
            modID: "acme.automation",
            modDirectoryPath: modDirectoryURL.path,
            definition: ModAutomationDefinition(
                id: "daily-sync",
                schedule: "0 * * * *",
                handler: ModExtensionHandler(command: [scriptURL.path])
            ),
            installID: "project:\(targetProject.id.uuidString.lowercased()):acme.automation",
            installScope: .project,
            installProjectID: targetProject.id,
            executionProjectID: targetProject.id,
            executionProjectPath: targetProject.path,
            executionThreadID: executionThread
        )
        model.activeExtensionAutomations = [resolved]

        let result = await model.executeAutomation(runtimeAutomationID: resolved.runtimeAutomationID)

        XCTAssertTrue(result)
        let capturedData = try Data(contentsOf: captureURL)
        let capturedInput = try JSONDecoder().decode(ExtensionWorkerInput.self, from: capturedData)
        XCTAssertEqual(capturedInput.project.id, targetProject.id.uuidString)
        XCTAssertEqual(capturedInput.project.path, targetProject.path)
        XCTAssertEqual(capturedInput.thread.id, executionThread.uuidString)
        XCTAssertNotEqual(capturedInput.project.id, otherProject.id.uuidString)
        XCTAssertNotEqual(capturedInput.thread.id, selectedThread.id.uuidString)
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeAutomationCaptureScript(directory: URL, captureURL: URL) throws -> URL {
        let scriptURL = directory.appendingPathComponent("automation.sh", isDirectory: false)
        let script = """
        #!/bin/sh
        input="$(cat)"
        printf '%s' "$input" > "\(captureURL.path)"
        echo '{"ok":true}'
        """
        try Data(script.utf8).write(to: scriptURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }
}
