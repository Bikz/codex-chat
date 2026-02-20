import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import CodexKit
import Foundation
import XCTest

@MainActor
final class VoiceCaptureRuntimeIntegrationTests: XCTestCase {
    func testVoiceCaptureTranscriptionDispatchesToRuntimeTurn() async throws {
        let harness = try await Harness.make(transcription: "voice pipeline check")
        defer { harness.cleanup() }

        await harness.model.loadInitialData()
        XCTAssertEqual(harness.model.runtimeStatus, .connected)
        XCTAssertNil(harness.model.runtimeIssue)

        harness.model.toggleVoiceCapture()
        try await eventually(timeoutSeconds: 3.0) {
            if case .recording = harness.model.voiceCaptureState {
                return true
            }
            return false
        }

        harness.model.toggleVoiceCapture()
        try await eventually(timeoutSeconds: 3.0) {
            harness.model.voiceCaptureState == .idle
        }

        XCTAssertEqual(harness.model.composerText, "voice pipeline check")
        XCTAssertEqual(harness.voiceService.startCaptureCallCount, 1)
        XCTAssertEqual(harness.voiceService.stopCaptureCallCount, 1)

        harness.model.submitComposerWithQueuePolicy()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.activeApprovalRequest != nil
        }

        harness.model.approvePendingApprovalOnce()

        try await eventually(timeoutSeconds: 3.0) {
            harness.model.canSendMessages
        }

        let archiveContent: String = try await eventuallyValue(timeoutSeconds: 3.0) {
            guard let archiveURL = ChatArchiveStore.latestArchiveURL(
                projectPath: harness.project.path,
                threadID: harness.thread.id
            ) else {
                return nil
            }
            guard let content = try? String(contentsOf: archiveURL, encoding: .utf8),
                  content.contains("voice pipeline check"),
                  content.contains("Hello from fake runtime.")
            else {
                return nil
            }
            return content
        }

        XCTAssertTrue(archiveContent.contains("voice pipeline check"))
    }

    @MainActor
    private struct Harness {
        let rootURL: URL
        let project: ProjectRecord
        let thread: ThreadRecord
        let runtime: CodexRuntime
        let model: AppModel
        let voiceService: MockVoiceCaptureService

        static func make(transcription: String) async throws -> Harness {
            let fakeCodexPath = try resolveFakeCodexPath()

            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("codexchat-voice-runtime-\(UUID().uuidString)", isDirectory: true)
            let projectURL = rootURL.appendingPathComponent("Project", isDirectory: true)
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

            let databaseURL = rootURL.appendingPathComponent("metadata.sqlite", isDirectory: false)
            let database = try MetadataDatabase(databaseURL: databaseURL)
            let repositories = MetadataRepositories(database: database)

            let project = try await repositories.projectRepository.createProject(
                named: "Voice Project",
                path: projectURL.path,
                trustState: .trusted,
                isGeneralProject: false
            )
            let thread = try await repositories.threadRepository.createThread(
                projectID: project.id,
                title: "Voice Thread"
            )

            let runtime = CodexRuntime(executableResolver: { fakeCodexPath })
            let voiceService = MockVoiceCaptureService(transcription: transcription)
            let model = AppModel(
                repositories: repositories,
                runtime: runtime,
                bootError: nil,
                voiceCaptureService: voiceService
            )
            model.selectedProjectID = project.id
            model.selectedThreadID = thread.id

            return Harness(
                rootURL: rootURL,
                project: project,
                thread: thread,
                runtime: runtime,
                model: model,
                voiceService: voiceService
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

@MainActor
private final class MockVoiceCaptureService: VoiceCaptureService, @unchecked Sendable {
    private let transcription: String
    private(set) var startCaptureCallCount = 0
    private(set) var stopCaptureCallCount = 0

    init(transcription: String) {
        self.transcription = transcription
    }

    func requestAuthorization() async -> VoiceCaptureAuthorizationStatus {
        .authorized
    }

    func startCapture() async throws {
        startCaptureCallCount += 1
    }

    func stopCapture() async throws -> String {
        stopCaptureCallCount += 1
        return transcription
    }

    func cancelCapture() async {}
}
