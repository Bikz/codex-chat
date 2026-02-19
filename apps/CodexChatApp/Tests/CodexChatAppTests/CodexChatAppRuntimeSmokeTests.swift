import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
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

    func testStaleRuntimeThreadMappingIsOverriddenOnFirstUse() async throws {
        let harness = try await Harness.make(trustState: .trusted)
        defer { harness.cleanup() }

        try await harness.repositories.runtimeThreadMappingRepository
            .setRuntimeThreadID(localThreadID: harness.thread.id, runtimeThreadID: "thr_stale")

        await harness.model.loadInitialData()
        harness.model.composerText = "Hello"
        harness.model.sendMessage()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.activeApprovalRequest != nil
        }

        let mappedRuntimeThreadID = try await harness.repositories.runtimeThreadMappingRepository
            .getRuntimeThreadID(localThreadID: harness.thread.id)
        XCTAssertEqual(mappedRuntimeThreadID, "thr_test")

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

        let content: String = try await eventuallyValue(timeoutSeconds: 3.0) { () -> String? in
            guard let archiveURL = ChatArchiveStore.latestArchiveURL(
                projectPath: harness.project.path,
                threadID: harness.thread.id
            ) else {
                return nil
            }

            guard let text = try? String(contentsOf: archiveURL, encoding: .utf8),
                  text.contains("status=completed"),
                  text.contains("Completed fileChange"),
                  text.contains("notes.txt")
            else {
                return nil
            }

            return text
        }

        XCTAssertTrue(content.contains("### Actions"))
        XCTAssertTrue(content.contains("Completed fileChange"))
        XCTAssertTrue(content.contains("notes.txt"))
    }

    func testRuntimeAutoRecoveryAfterUnexpectedTermination() async throws {
        let harness = try await Harness.make(trustState: .trusted)
        defer { harness.cleanup() }

        await harness.model.loadInitialData()
        XCTAssertEqual(harness.model.runtimeStatus, .connected)

        harness.model.handleRuntimeTermination(detail: "Simulated unexpected runtime exit.")

        try await eventually(timeoutSeconds: 8.0) {
            harness.model.runtimeStatus == .connected && harness.model.runtimeIssue == nil
        }
    }

    func testBusyComposerSubmissionQueuesAndAutoDrains() async throws {
        let harness = try await Harness.make(trustState: .trusted)
        defer { harness.cleanup() }

        await harness.model.loadInitialData()

        harness.model.composerText = "First turn"
        harness.model.submitComposerWithQueuePolicy()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.activeApprovalRequest != nil
        }

        harness.model.composerText = "Queued follow-up"
        harness.model.submitComposerWithQueuePolicy()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.selectedFollowUpQueueItems.contains(where: { $0.text == "Queued follow-up" })
        }

        harness.model.approvePendingApprovalOnce()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.activeApprovalRequest != nil
                && !harness.model.selectedFollowUpQueueItems.contains(where: { $0.text == "Queued follow-up" })
        }
    }

    func testCapabilityRuntimeSuggestionsQueueAsManual() async throws {
        let steerFixture = try Self.resolveFakeCodexSteerPath()
        let harness = try await Harness.make(trustState: .trusted, fakeCodexPath: steerFixture)
        defer { harness.cleanup() }

        await harness.model.loadInitialData()
        XCTAssertTrue(harness.model.runtimeCapabilities.supportsFollowUpSuggestions)

        harness.model.composerText = "Kick off"
        harness.model.submitComposerWithQueuePolicy()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.selectedFollowUpQueueItems.count >= 2
        }

        XCTAssertTrue(harness.model.selectedFollowUpQueueItems.allSatisfy { $0.dispatchMode == .manual })
        XCTAssertTrue(harness.model.selectedFollowUpQueueItems.allSatisfy { $0.source == .assistantSuggestion })
    }

    func testSteerWhileBusyUsesInFlightSteerWhenSupported() async throws {
        let steerFixture = try Self.resolveFakeCodexSteerPath()
        let harness = try await Harness.make(trustState: .trusted, fakeCodexPath: steerFixture)
        defer { harness.cleanup() }

        await harness.model.loadInitialData()
        harness.model.composerText = "Start turn"
        harness.model.submitComposerWithQueuePolicy()

        try await eventually(timeoutSeconds: 3.0) {
            !harness.model.selectedFollowUpQueueItems.isEmpty && harness.model.isTurnInProgress
        }

        let item = try XCTUnwrap(harness.model.selectedFollowUpQueueItems.first)
        harness.model.steerFollowUp(item.id)

        try await eventually(timeoutSeconds: 3.0) {
            !harness.model.selectedFollowUpQueueItems.contains(where: { $0.id == item.id })
                && harness.model.canSendMessages
        }
    }

    func testSteerWhileBusyWithoutCapabilityQueuesAsNextAuto() async throws {
        let harness = try await Harness.make(trustState: .trusted)
        defer { harness.cleanup() }

        await harness.model.loadInitialData()
        harness.model.composerText = "Start legacy turn"
        harness.model.submitComposerWithQueuePolicy()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.activeApprovalRequest != nil
        }

        harness.model.composerText = "queue-a"
        harness.model.submitComposerWithQueuePolicy()
        harness.model.composerText = "queue-b"
        harness.model.submitComposerWithQueuePolicy()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.selectedFollowUpQueueItems.count == 2
        }

        let target = harness.model.selectedFollowUpQueueItems[1]
        harness.model.steerFollowUp(target.id)

        try await eventually(timeoutSeconds: 3.0) {
            guard let head = harness.model.selectedFollowUpQueueItems.first else {
                return false
            }
            return head.id == target.id && head.dispatchMode == .auto
        }
    }

    func testAutoDrainContinuesAfterSwitchingThreads() async throws {
        let harness = try await Harness.make(trustState: .trusted)
        defer { harness.cleanup() }

        await harness.model.loadInitialData()
        let firstThreadID = harness.thread.id

        harness.model.composerText = "first-thread-start"
        harness.model.submitComposerWithQueuePolicy()
        try await eventually(timeoutSeconds: 3.0) {
            harness.model.activeApprovalRequest != nil
        }

        harness.model.composerText = "first-thread-queued"
        harness.model.submitComposerWithQueuePolicy()
        try await eventually(timeoutSeconds: 3.0) {
            harness.model.selectedFollowUpQueueItems.contains(where: { $0.text == "first-thread-queued" })
        }

        let secondThread = try await harness.repositories.threadRepository.createThread(
            projectID: harness.project.id,
            title: "Second Thread"
        )
        try await harness.model.refreshThreads()
        harness.model.selectThread(secondThread.id)
        try await eventually(timeoutSeconds: 3.0) {
            harness.model.selectedThreadID == secondThread.id
        }

        harness.model.approvePendingApprovalOnce()

        try await eventually(timeoutSeconds: 3.0) {
            let entries = harness.model.transcriptStore[firstThreadID, default: []]
            return entries.contains { entry in
                guard case let .message(message) = entry else { return false }
                return message.role == .user && message.text == "first-thread-queued"
            }
        }
    }

    @MainActor
    private struct Harness {
        let rootURL: URL
        let project: ProjectRecord
        let thread: ThreadRecord
        let repositories: MetadataRepositories
        let runtime: CodexRuntime
        let model: AppModel

        static func make(trustState: ProjectTrustState) async throws -> Harness {
            let fakeCodexPath = try resolveFakeCodexPath()
            return try await make(trustState: trustState, fakeCodexPath: fakeCodexPath)
        }

        static func make(trustState: ProjectTrustState, fakeCodexPath: String) async throws -> Harness {
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
                trustState: trustState,
                isGeneralProject: false
            )
            let thread = try await repositories.threadRepository.createThread(
                projectID: project.id,
                title: "Fixture Thread"
            )

            let runtime = CodexRuntime(executableResolver: { fakeCodexPath })

            let model = AppModel(repositories: repositories, runtime: runtime, bootError: nil)
            model.selectedProjectID = project.id
            model.selectedThreadID = thread.id
            return Harness(
                rootURL: rootURL,
                project: project,
                thread: thread,
                repositories: repositories,
                runtime: runtime,
                model: model
            )
        }

        func cleanup() {
            let stopGroup = DispatchGroup()
            stopGroup.enter()
            Task {
                await runtime.stop()
                stopGroup.leave()
            }
            _ = stopGroup.wait(timeout: .now() + 5)
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

    private static func resolveFakeCodexSteerPath(filePath: String = #filePath) throws -> String {
        var url = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while url.path != "/" {
            if fileManager.fileExists(atPath: url.appendingPathComponent("pnpm-workspace.yaml").path) {
                return url.appendingPathComponent("tests/fixtures/fake-codex-steer").path
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
