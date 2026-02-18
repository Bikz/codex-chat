@testable import CodexChatShared
import CodexKit
import XCTest

@MainActor
final class ComposerStarterPromptTests: XCTestCase {
    func testStarterPromptsVisibleOnlyWhenComposerIsEmpty() {
        let model = makeReadyModel()
        XCTAssertTrue(model.shouldShowComposerStarterPrompts)

        model.composerText = "Need help with this project"
        XCTAssertFalse(model.shouldShowComposerStarterPrompts)

        model.composerText = "   "
        XCTAssertTrue(model.shouldShowComposerStarterPrompts)
    }

    func testInsertStarterPromptPopulatesComposerAndHidesStarterPrompts() {
        let model = makeReadyModel()
        let prompt = "What's on my calendar today?"
        model.insertStarterPrompt(prompt)

        XCTAssertEqual(model.composerText, prompt)
        XCTAssertFalse(model.shouldShowComposerStarterPrompts)
    }

    func testHandleVoiceTranscriptionResultPreservesExistingComposerText() {
        let model = makeReadyModel()
        model.composerText = "Plan today's tasks."

        model.handleVoiceTranscriptionResult("Set up OpenClaw on a VM using Google CLI.")

        XCTAssertEqual(
            model.composerText,
            "Plan today's tasks.\n\nSet up OpenClaw on a VM using Google CLI."
        )
        XCTAssertEqual(model.voiceCaptureState, .idle)
    }

    func testHandleVoiceTranscriptionResultWithEmptyTextSetsFailedState() {
        let model = makeReadyModel()
        model.handleVoiceTranscriptionResult("   ")

        guard case let .failed(message) = model.voiceCaptureState else {
            XCTFail("Expected failed state when transcription text is empty")
            return
        }

        XCTAssertTrue(message.contains("No speech detected"))
    }

    func testCancelVoiceCapturePreservesExistingComposerText() {
        let model = makeReadyModel()
        model.composerText = "Existing draft"

        model.cancelVoiceCapture()

        XCTAssertEqual(model.composerText, "Existing draft")
    }

    func testCancelVoiceCaptureLeavesStateIdleWithoutHiddenShortcutDependency() {
        let model = makeReadyModel()
        model.voiceCaptureState = .failed(message: "Mic not available")

        model.cancelVoiceCapture()

        XCTAssertEqual(model.voiceCaptureState, .idle)
    }

    private func makeReadyModel() -> AppModel {
        let model = AppModel(
            repositories: nil,
            runtime: CodexRuntime(executableResolver: { nil }),
            bootError: nil
        )
        model.selectedProjectID = UUID()
        model.selectedThreadID = UUID()
        model.runtimeStatus = .connected
        model.accountState = RuntimeAccountState(account: nil, authMode: .unknown, requiresOpenAIAuth: false)
        return model
    }
}
