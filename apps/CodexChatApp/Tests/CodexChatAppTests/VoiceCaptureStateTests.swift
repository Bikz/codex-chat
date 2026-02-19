@testable import CodexChatShared
import CodexKit
import XCTest

@MainActor
final class VoiceCaptureStateTests: XCTestCase {
    func testVoiceCaptureTransitionsIdleToRecordingToIdleAndAppendsTranscript() async throws {
        let voiceService = MockVoiceCaptureService()
        voiceService.authorizationStatus = .authorized
        voiceService.stopResult = .success("calendar check for today")

        let model = makeReadyModel(voiceService: voiceService)

        model.toggleVoiceCapture()
        try await eventually(timeoutSeconds: 2.0) {
            if case .recording = model.voiceCaptureState {
                return true
            }
            return false
        }

        model.toggleVoiceCapture()
        try await eventually(timeoutSeconds: 1.0) {
            model.voiceCaptureState == .idle
        }

        XCTAssertEqual(model.composerText, "calendar check for today")
        XCTAssertEqual(voiceService.startCaptureCallCount, 1)
        XCTAssertEqual(voiceService.stopCaptureCallCount, 1)
    }

    func testVoiceCapturePermissionDeniedTransitionsToFailed() async throws {
        let voiceService = MockVoiceCaptureService()
        voiceService.authorizationStatus = .denied(reason: "Speech recognition access was denied.")

        let model = makeReadyModel(voiceService: voiceService)
        model.toggleVoiceCapture()

        try await eventually(timeoutSeconds: 1.0) {
            if case .failed = model.voiceCaptureState {
                return true
            }
            return false
        }

        guard case let .failed(message) = model.voiceCaptureState else {
            XCTFail("Expected failed state")
            return
        }
        XCTAssertTrue(message.contains("denied"))
        XCTAssertEqual(voiceService.startCaptureCallCount, 0)
    }

    func testVoiceCaptureAutoStopsAtConfiguredLimit() async throws {
        let voiceService = MockVoiceCaptureService()
        voiceService.authorizationStatus = .authorized
        voiceService.stopResult = .success("auto-stopped transcription")

        let model = makeReadyModel(voiceService: voiceService)
        model.voiceAutoStopDurationNanoseconds = 30_000_000

        model.toggleVoiceCapture()
        try await eventually(timeoutSeconds: 1.0) {
            model.voiceCaptureState == .idle
        }

        XCTAssertEqual(model.composerText, "auto-stopped transcription")
        XCTAssertEqual(voiceService.stopCaptureCallCount, 1)
    }

    func testCancelVoiceCaptureWhileRecordingResetsToIdle() async throws {
        let voiceService = MockVoiceCaptureService()
        voiceService.authorizationStatus = .authorized
        voiceService.stopResult = .success("should not be used")

        let model = makeReadyModel(voiceService: voiceService)
        model.toggleVoiceCapture()
        try await eventually(timeoutSeconds: 8.0) {
            if case .recording = model.voiceCaptureState {
                return true
            }
            return false
        }

        model.cancelVoiceCapture()
        XCTAssertEqual(model.voiceCaptureState, .idle)
        XCTAssertEqual(voiceService.cancelCaptureCallCount, 1)
    }

    func testVoiceCaptureElapsedTextClearsWhenRecordingStops() async throws {
        let voiceService = MockVoiceCaptureService()
        voiceService.authorizationStatus = .authorized
        voiceService.stopResult = .success("done")

        let model = makeReadyModel(voiceService: voiceService)
        model.toggleVoiceCapture()

        try await eventually(timeoutSeconds: 3.0) {
            model.isVoiceCaptureRecording && model.voiceCaptureElapsedText != nil
        }

        model.toggleVoiceCapture()

        try await eventually(timeoutSeconds: 3.0) {
            model.voiceCaptureState == .idle
        }

        XCTAssertNil(model.voiceCaptureElapsedText)
    }

    private func makeReadyModel(voiceService: MockVoiceCaptureService) -> AppModel {
        let model = AppModel(
            repositories: nil,
            runtime: CodexRuntime(executableResolver: { nil }),
            bootError: nil,
            voiceCaptureService: voiceService
        )
        model.selectedProjectID = UUID()
        model.selectedThreadID = UUID()
        model.runtimeStatus = .connected
        model.accountState = RuntimeAccountState(account: nil, authMode: .unknown, requiresOpenAIAuth: false)
        return model
    }

    private func eventually(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw XCTestError(.failureWhileWaiting)
    }
}

@MainActor
private final class MockVoiceCaptureService: VoiceCaptureService {
    var authorizationStatus: VoiceCaptureAuthorizationStatus = .authorized
    var startError: Error?
    var stopResult: Result<String, Error> = .success("mock transcript")

    private(set) var startCaptureCallCount = 0
    private(set) var stopCaptureCallCount = 0
    private(set) var cancelCaptureCallCount = 0

    func requestAuthorization() async -> VoiceCaptureAuthorizationStatus {
        authorizationStatus
    }

    func startCapture() throws {
        startCaptureCallCount += 1
        if let startError {
            throw startError
        }
    }

    func stopCapture() async throws -> String {
        stopCaptureCallCount += 1
        switch stopResult {
        case let .success(text):
            return text
        case let .failure(error):
            throw error
        }
    }

    func cancelCapture() {
        cancelCaptureCallCount += 1
    }
}
