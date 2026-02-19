import CodexChatCore
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

    func testStarterPromptsHideWhenComposerHasAttachments() {
        let model = makeReadyModel()
        model.composerAttachments = [
            AppModel.ComposerAttachment(
                path: "/tmp/screenshot.png",
                name: "screenshot.png",
                kind: .localImage
            ),
        ]

        XCTAssertFalse(model.shouldShowComposerStarterPrompts)
    }

    func testStarterPromptsHideWhenConversationHasEntries() {
        let model = makeReadyModel()
        let threadID = model.selectedThreadID ?? UUID()
        let existingMessage = ChatMessage(
            threadId: threadID,
            role: .user,
            text: "Existing conversation context"
        )
        model.conversationState = .loaded([.message(existingMessage)])

        XCTAssertFalse(model.shouldShowComposerStarterPrompts)
    }

    func testCanSubmitComposerInputRequiresDraftContent() {
        let model = makeReadyModel()
        XCTAssertFalse(model.canSubmitComposerInput)

        model.composerText = "Draft message"
        XCTAssertTrue(model.canSubmitComposerInput)

        model.composerText = "   "
        model.composerAttachments = [
            AppModel.ComposerAttachment(
                path: "/tmp/notes.md",
                name: "notes.md",
                kind: .mentionFile
            ),
        ]
        XCTAssertTrue(model.canSubmitComposerInput)
    }

    func testRuntimeInputItemsMapFromComposerAttachments() {
        let model = makeReadyModel()
        let attachments = [
            AppModel.ComposerAttachment(
                path: "/tmp/example.png",
                name: "example.png",
                kind: .localImage
            ),
            AppModel.ComposerAttachment(
                path: "/tmp/README.md",
                name: "README.md",
                kind: .mentionFile
            ),
        ]

        let inputItems = model.runtimeInputItemsForComposerAttachments(attachments)
        XCTAssertEqual(inputItems.count, 2)

        if case let .localImage(path) = inputItems[0] {
            XCTAssertEqual(path, "/tmp/example.png")
        } else {
            XCTFail("Expected first input item to be localImage")
        }

        if case let .mention(name, path) = inputItems[1] {
            XCTAssertEqual(name, "README.md")
            XCTAssertEqual(path, "/tmp/README.md")
        } else {
            XCTFail("Expected second input item to be mention")
        }
    }

    func testComposerMemoryModeOverrideResolvesAgainstProjectDefaults() {
        let model = makeReadyModel()
        let project = ProjectRecord(
            name: "Workspace",
            path: "/tmp/workspace",
            trustState: .trusted,
            memoryWriteMode: .summariesOnly
        )

        model.composerMemoryMode = .projectDefault
        XCTAssertEqual(model.effectiveComposerMemoryWriteMode(for: project), .summariesOnly)

        model.composerMemoryMode = .off
        XCTAssertEqual(model.effectiveComposerMemoryWriteMode(for: project), .off)

        model.composerMemoryMode = .summariesAndKeyFacts
        XCTAssertEqual(model.effectiveComposerMemoryWriteMode(for: project), .summariesAndKeyFacts)
    }

    func testSubmitComposerWithAttachmentsWhileBusyKeepsDraftAndShowsMessage() {
        let model = makeReadyModel()
        model.isTurnInProgress = true
        model.composerAttachments = [
            AppModel.ComposerAttachment(
                path: "/tmp/context.png",
                name: "context.png",
                kind: .localImage
            ),
        ]
        model.composerText = "Use this image"

        model.submitComposerWithQueuePolicy()

        XCTAssertEqual(model.composerText, "Use this image")
        XCTAssertEqual(model.composerAttachments.count, 1)
        XCTAssertTrue(model.followUpStatusMessage?.contains("can't be queued") ?? false)
    }

    func testAddComposerAttachmentsDoesNotShowAttachedCountStatusMessage() throws {
        let model = makeReadyModel()
        model.followUpStatusMessage = "Keep this status"

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try "Attachment test".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        model.addComposerAttachments([tempFile])

        XCTAssertEqual(model.composerAttachments.count, 1)
        XCTAssertEqual(model.followUpStatusMessage, "Keep this status")
    }

    func testAddComposerAttachmentsTreatsDroppedFolderAsMentionFile() throws {
        let model = makeReadyModel()
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("composer-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        model.addComposerAttachments([folderURL])

        XCTAssertEqual(model.composerAttachments.count, 1)
        XCTAssertEqual(model.composerAttachments.first?.kind, .mentionFile)
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
        model.conversationState = .loaded([])
        model.runtimeStatus = .connected
        model.accountState = RuntimeAccountState(account: nil, authMode: .unknown, requiresOpenAIAuth: false)
        return model
    }
}
