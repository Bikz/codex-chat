import CodexChatInfra
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

        let launchdDirectory = storagePaths.systemURL.appendingPathComponent("launchd", isDirectory: true)
        let payload = try XCTUnwrap(
            model.backgroundAutomationLaunchPayload(
                for: automation,
                label: "app.codexchat.test",
                launchdDirectory: launchdDirectory
            )
        )
        let wrapperPath = try model.ensureBackgroundAutomationWrapperCommand()
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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let resultURL = launchdDirectory.appendingPathComponent("app.codexchat.test.result.json", isDirectory: false)
        let result = try decoder.decode(BackgroundAutomationRunResult.self, from: Data(contentsOf: resultURL))
        XCTAssertEqual(result.modID, "acme.background")
        XCTAssertEqual(result.automationID, "daily-sync")
        XCTAssertEqual(result.status, "launchd-ok")
        XCTAssertEqual(result.launchdLabel, "app.codexchat.test")
        XCTAssertNil(result.error)
    }

    func testRefreshAutomationHealthSummaryImportsBackgroundRunResults() async throws {
        let rootURL = try makeTempDirectory(prefix: "background-automation-import")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let storagePaths = CodexChatStoragePaths(rootURL: rootURL)
        try storagePaths.ensureRootStructure()

        let databaseURL = rootURL.appendingPathComponent("metadata.sqlite", isDirectory: false)
        let database = try MetadataDatabase(databaseURL: databaseURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths
        )

        let launchdDirectory = storagePaths.systemURL.appendingPathComponent("launchd", isDirectory: true)
        try FileManager.default.createDirectory(at: launchdDirectory, withIntermediateDirectories: true)

        let completedAt = Date()
        let result = BackgroundAutomationRunResult(
            installID: "project:00000000-0000-0000-0000-000000000001:acme.background",
            modID: "acme.background",
            automationID: "weekday-sync",
            schedule: "30 9 * * 1,3,5",
            launchdLabel: "app.codexchat.test",
            completedAt: completedAt,
            status: "launchd-run-failed",
            error: "worker exploded"
        )

        let resultURL = launchdDirectory.appendingPathComponent("app.codexchat.test.result.json", isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result).write(to: resultURL, options: [.atomic])

        await model.refreshAutomationHealthSummary(for: "acme.background")

        let summary = try XCTUnwrap(model.extensionAutomationHealthByModID["acme.background"])
        XCTAssertEqual(summary.lastStatus, "launchd-run-failed")
        XCTAssertEqual(summary.lastError, "worker exploded")
        XCTAssertEqual(summary.launchdScheduledAutomationCount, 1)
        XCTAssertEqual(summary.launchdFailingAutomationCount, 1)
        XCTAssertNotNil(summary.lastRunAt)
        XCTAssertNotNil(summary.nextRunAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resultURL.path))

        let records = try await repositories.extensionAutomationStateRepository.list(modID: "acme.background")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].lastStatus, "launchd-run-failed")
        XCTAssertEqual(records[0].lastError, "worker exploded")
        XCTAssertEqual(records[0].launchdLabel, "app.codexchat.test")
        XCTAssertNotNil(records[0].lastRunAt)
        XCTAssertNotNil(records[0].nextRunAt)
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
