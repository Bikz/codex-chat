@testable import CodexChatShared
import CodexExtensions
import CodexMods
import Foundation
import XCTest

@MainActor
final class BackgroundAutomationRunnerTests: XCTestCase {
    func testBackgroundAutomationWrapperRunsSharedWorkerContract() throws {
        let rootURL = try makeTempDirectory(prefix: "background-automation-runner")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let storagePaths = CodexChatStoragePaths(rootURL: rootURL)
        try storagePaths.ensureRootStructure()
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil, storagePaths: storagePaths)

        let projectURL = rootURL.appendingPathComponent("project", isDirectory: true)
        let modDirectoryURL = rootURL.appendingPathComponent("mod", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modDirectoryURL, withIntermediateDirectories: true)

        let projectID = UUID()
        let threadID = UUID()
        let captureURL = modDirectoryURL.appendingPathComponent("automation-input.json", isDirectory: false)
        let scriptURL = try makeBackgroundAutomationScript(
            directory: modDirectoryURL,
            captureURL: captureURL
        )
        let automation = AppModel.ResolvedExtensionAutomation(
            modID: "acme.background",
            modDirectoryPath: modDirectoryURL.path,
            definition: ModAutomationDefinition(
                id: "daily-sync",
                schedule: "0 * * * *",
                handler: ModExtensionHandler(command: [scriptURL.path], cwd: "."),
                permissions: .init(runWhenAppClosed: true)
            ),
            installID: "project:\(projectID.uuidString.lowercased()):acme.background",
            installScope: .project,
            installProjectID: projectID,
            executionProjectID: projectID,
            executionProjectPath: projectURL.path,
            executionThreadID: threadID
        )

        let payload = try XCTUnwrap(model.backgroundAutomationLaunchPayload(for: automation))
        let wrapperPath = try model.ensureBackgroundAutomationWrapperCommand()
        let launchdDirectory = storagePaths.systemURL.appendingPathComponent("launchd", isDirectory: true)
        let payloadURL = try model.writeBackgroundAutomationLaunchPayload(
            payload,
            label: "app.codexchat.test",
            launchdDirectory: launchdDirectory
        )

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: wrapperPath)
        process.arguments = ["run", "--payload", payloadURL.path]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "stdout=\(stdout)\nstderr=\(stderr)")

        let capturedData = try Data(contentsOf: captureURL)
        let capturedInput = try JSONDecoder().decode(ExtensionWorkerInput.self, from: capturedData)
        XCTAssertEqual(capturedInput.event, "automation.scheduled")
        XCTAssertEqual(capturedInput.project.id, projectID.uuidString)
        XCTAssertEqual(capturedInput.project.path, projectURL.path)
        XCTAssertEqual(capturedInput.thread.id, threadID.uuidString)

        let modsBarOutputURL = modDirectoryURL
            .appendingPathComponent(".codexchat", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("modsBar-project-\(projectID.uuidString).json", isDirectory: false)
        let modsBarData = try Data(contentsOf: modsBarOutputURL)
        let modsBarOutput = try JSONDecoder().decode(ExtensionModsBarOutput.self, from: modsBarData)
        XCTAssertEqual(modsBarOutput.scope, .project)
        XCTAssertEqual(modsBarOutput.markdown, "Background summary")

        let artifactURL = projectURL.appendingPathComponent("notes/daily.txt", isDirectory: false)
        XCTAssertEqual(try String(contentsOf: artifactURL, encoding: .utf8), "scheduled artifact")
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeBackgroundAutomationScript(directory: URL, captureURL: URL) throws -> URL {
        let scriptURL = directory.appendingPathComponent("automation.sh", isDirectory: false)
        let script = """
        #!/bin/sh
        input="$(cat)"
        printf '%s' "$input" > "\(captureURL.path)"
        printf '%s\\n' \
        '{"ok":true,"log":"background automation tick",'\
        '"modsBar":{"title":"Daily","markdown":"Background summary","scope":"project"},'\
        '"artifacts":[{"path":"notes/daily.txt","op":"upsert","content":"scheduled artifact"}]}'
        """
        try Data(script.utf8).write(to: scriptURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }
}
