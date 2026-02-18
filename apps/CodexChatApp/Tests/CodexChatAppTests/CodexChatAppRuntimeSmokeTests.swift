@testable import CodexChatApp
import CodexChatCore
import CodexChatInfra
import CodexKit
import Foundation
import XCTest

@MainActor
final class CodexChatAppRuntimeSmokeTests: XCTestCase {
    func testAskActReviewJourneyPersistsThreadMappingAndArchive() async throws {
        let harness = try await Harness.make(trustState: .trusted)
        defer { harness.cleanup() }

        await harness.model.loadInitialData()
        XCTAssertEqual(harness.model.runtimeStatus, .connected)
        XCTAssertNil(harness.model.runtimeIssue)

        XCTAssertEqual(harness.model.selectedProjectID, harness.project.id)
        XCTAssertEqual(harness.model.selectedThreadID, harness.thread.id)

        harness.model.composerText = "Hello"
        harness.model.sendMessage()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.activeApprovalRequest != nil
        }

        harness.model.approvePendingApprovalOnce()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.canReviewChanges
        }

        XCTAssertTrue(harness.model.selectedThreadChanges.contains(where: { $0.path == "notes.txt" }))

        let mappedRuntimeThreadID = try await harness.repositories.runtimeThreadMappingRepository
            .getRuntimeThreadID(localThreadID: harness.thread.id)
        XCTAssertEqual(mappedRuntimeThreadID, "thr_test")

        let archiveURL = try await eventuallyValue(timeoutSeconds: 3.0) {
            ChatArchiveStore.latestArchiveURL(projectPath: harness.project.path, threadID: harness.thread.id)
        }
        let archiveContent = try String(contentsOf: archiveURL, encoding: .utf8)
        XCTAssertTrue(archiveContent.contains("Hello"))
        XCTAssertTrue(archiveContent.contains("Hello from fake runtime."))
    }

    func testSendDisablesDuringTurnAndReenablesAfterCompletion() async throws {
        let harness = try await Harness.make(trustState: .trusted)
        defer { harness.cleanup() }

        await harness.model.loadInitialData()
        XCTAssertTrue(harness.model.canSendMessages)

        harness.model.composerText = "Hello"
        harness.model.sendMessage()

        XCTAssertFalse(harness.model.canSendMessages)

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.activeApprovalRequest != nil
        }

        harness.model.approvePendingApprovalOnce()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.canSendMessages
        }
    }

    func testSafeEscalationUpdatesSafetySettingsButApprovalsStillAppear() async throws {
        let harness = try await Harness.make(trustState: .untrusted)
        defer { harness.cleanup() }

        await harness.model.loadInitialData()
        XCTAssertEqual(harness.model.selectedProject?.sandboxMode, .readOnly)
        XCTAssertEqual(harness.model.selectedProject?.approvalPolicy, .untrusted)

        harness.model.updateSelectedProjectSafetySettings(
            sandboxMode: .workspaceWrite,
            approvalPolicy: .onRequest,
            networkAccess: false,
            webSearch: .cached
        )

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.selectedProject?.sandboxMode == .workspaceWrite
                && harness.model.selectedProject?.approvalPolicy == .onRequest
        }

        harness.model.composerText = "Trigger turn"
        harness.model.sendMessage()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.activeApprovalRequest != nil
        }
    }

    func testArchiveWrittenOnTurnCompletionIncludesActionSummary() async throws {
        let harness = try await Harness.make(trustState: .trusted)
        defer { harness.cleanup() }

        await harness.model.loadInitialData()
        harness.model.composerText = "Archive check"
        harness.model.sendMessage()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.activeApprovalRequest != nil
        }
        harness.model.approvePendingApprovalOnce()

        let archiveURL = try await eventuallyValue(timeoutSeconds: 3.0) {
            ChatArchiveStore.latestArchiveURL(projectPath: harness.project.path, threadID: harness.thread.id)
        }

        let content = try String(contentsOf: archiveURL, encoding: .utf8)
        XCTAssertTrue(content.contains("### Actions"))
        XCTAssertTrue(content.contains("Completed fileChange"))
        XCTAssertTrue(content.contains("notes.txt"))
    }

    @MainActor
    private struct Harness {
        let rootURL: URL
        let projectURL: URL
        let project: ProjectRecord
        let thread: ThreadRecord
        let repositories: MetadataRepositories
        let runtime: CodexRuntime
        let model: AppModel

        static func make(trustState: ProjectTrustState) async throws -> Harness {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("codexchat-runtime-smoke-\(UUID().uuidString)", isDirectory: true)
            let projectURL = rootURL.appendingPathComponent("Project", isDirectory: true)
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

            let databaseURL = rootURL.appendingPathComponent("metadata.sqlite", isDirectory: false)
            let database = try MetadataDatabase(databaseURL: databaseURL)
            let repositories = MetadataRepositories(database: database)

            let project = try await repositories.projectRepository.createProject(
                named: "Fixture Project",
                path: projectURL.path,
                trustState: trustState
            )
            let thread = try await repositories.threadRepository.createThread(
                projectID: project.id,
                title: "Fixture Thread"
            )

            let fakeCodexPath = try resolveFakeCodexPath()
            let runtime = CodexRuntime(executableResolver: { fakeCodexPath })

            let model = AppModel(repositories: repositories, runtime: runtime, bootError: nil)
            model.selectedProjectID = project.id
            model.selectedThreadID = thread.id
            return Harness(
                rootURL: rootURL,
                projectURL: projectURL,
                project: project,
                thread: thread,
                repositories: repositories,
                runtime: runtime,
                model: model
            )
        }

        func cleanup() {
            Task {
                await runtime.stop()
            }
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    private static func resolveFakeCodexPath(filePath: String = #filePath) throws -> String {
        var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while url.path != "/" {
            if fileManager.fileExists(atPath: url.appendingPathComponent("pnpm-workspace.yaml").path) {
                return url.appendingPathComponent("tests/fixtures/fake-codex").path
            }
            url.deleteLastPathComponent()
        }

        throw XCTSkip("Unable to locate repo root from \(filePath)")
    }

    private func eventually(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw XCTestError(.failureWhileWaiting)
    }

    private func eventuallyValue<T>(
        timeoutSeconds: TimeInterval,
        value: @escaping () -> T?
    ) async throws -> T {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let value = value() {
                return value
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw XCTestError(.failureWhileWaiting)
    }
}
