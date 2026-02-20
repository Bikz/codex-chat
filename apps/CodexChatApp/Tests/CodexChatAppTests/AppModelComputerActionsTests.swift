import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import CodexComputerActions
import XCTest

@MainActor
final class AppModelComputerActionsTests: XCTestCase {
    func testConfirmClearsPendingPreviewImmediately() async throws {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let request = ComputerActionRequest(
            runContextID: "run-1",
            arguments: ["recipient": "+15551234567", "body": "Hello"]
        )
        let artifact = ComputerActionPreviewArtifact(
            actionID: "messages.send",
            runContextID: "run-1",
            title: "Message Draft Preview",
            summary: "Ready to send a message.",
            detailsMarkdown: "Test"
        )

        model.pendingComputerActionPreview = AppModel.PendingComputerActionPreview(
            threadID: UUID(),
            projectID: UUID(),
            request: request,
            artifact: artifact,
            providerActionID: "unknown.action",
            providerDisplayName: "Unknown",
            safetyLevel: .externallyVisible,
            requiresConfirmation: true
        )

        model.confirmPendingComputerActionPreview()

        XCTAssertNil(model.pendingComputerActionPreview)

        try await eventually(timeoutSeconds: 1.0) {
            model.computerActionStatusMessage?.contains("Unknown computer action") == true
        }
    }

    func testAdaptiveIntentParsesCalendarCheckPhrases() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let first = model.adaptiveIntent(for: "Can you check my calendar today?")
        XCTAssertEqual(first, .calendarToday(rangeHours: 24))

        let second = model.adaptiveIntent(for: "show my calendar for the next 8 hours")
        XCTAssertEqual(second, .calendarToday(rangeHours: 8))
    }

    func testAdaptiveIntentParsesRemindersCheckPhrases() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let first = model.adaptiveIntent(for: "Can you check my reminders today?")
        XCTAssertEqual(first, .remindersToday(rangeHours: 24))

        let second = model.adaptiveIntent(for: "show reminders for the next 6 hours")
        XCTAssertEqual(second, .remindersToday(rangeHours: 6))
    }

    func testMaybeHandleAdaptiveIntentRoutesNativeActionsOnly() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        XCTAssertTrue(
            model.maybeHandleAdaptiveIntentFromComposer(
                text: "check my calendar today",
                attachments: []
            )
        )

        XCTAssertFalse(
            model.maybeHandleAdaptiveIntentFromComposer(
                text: "run plan ./docs/plan.md",
                attachments: []
            )
        )
    }

    func testPermissionRecoveryTargetMapsMessagesAutomationErrors() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let target = model.permissionRecoveryTargetForComputerAction(
            actionID: "messages.send",
            error: .permissionDenied(
                "Messages send failed. Check Messages permissions in System Settings > Privacy & Security > Automation."
            )
        )

        XCTAssertEqual(target, .automation)
    }

    func testPermissionRecoveryTargetMapsCalendarErrors() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let target = model.permissionRecoveryTargetForComputerAction(
            actionID: "calendar.today",
            error: .permissionDenied(
                "Calendar access is denied. Enable Calendar permissions in System Settings > Privacy & Security > Calendars."
            )
        )

        XCTAssertEqual(target, .calendars)
    }

    func testPermissionRecoveryTargetMapsRemindersErrors() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let target = model.permissionRecoveryTargetForComputerAction(
            actionID: "reminders.today",
            error: .permissionDenied(
                "Reminders access is denied. Enable Reminders permissions in System Settings > Privacy & Security > Reminders."
            )
        )

        XCTAssertEqual(target, .reminders)
    }

    func testPermissionRecoveryTargetUsesScriptHintFallback() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let target = model.permissionRecoveryTargetForComputerAction(
            actionID: "apple.script.run",
            error: .permissionDenied(
                "Script execution was blocked by macOS permissions. Enable access in System Settings > Privacy & Security > Automation."
            ),
            arguments: ["targetHint": "reminders"]
        )

        XCTAssertEqual(target, .reminders)
    }

    func testPermissionRecoveryTargetIgnoresAppLevelDeny() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let target = model.permissionRecoveryTargetForComputerAction(
            actionID: "messages.send",
            error: .permissionDenied("Permission denied for Messages Send.")
        )

        XCTAssertNil(target)
    }

    func testPreviewPermissionFailureSetsInlineRecoveryNotice() async throws {
        let deniedCalendar = CalendarTodayAction(
            eventSource: PermissionDeniedCalendarSource(),
            nowProvider: Date.init
        )
        let registry = ComputerActionRegistry(calendarToday: deniedCalendar)
        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil,
            computerActionRegistry: registry
        )

        do {
            try await model.runNativeComputerAction(
                actionID: "calendar.today",
                arguments: ["rangeHours": "24"],
                threadID: UUID(),
                projectID: UUID()
            )
            XCTFail("Expected preview permission failure")
        } catch let error as ComputerActionError {
            guard case .permissionDenied = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }

        XCTAssertEqual(model.permissionRecoveryNotice?.target, .calendars)
    }

    func testExecutePermissionFailureSetsInlineRecoveryNotice() async throws {
        let deniedMessages = MessagesSendAction(sender: PermissionDeniedMessagesSender())
        let registry = ComputerActionRegistry(messagesSend: deniedMessages)
        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil,
            computerActionRegistry: registry
        )

        try await model.runNativeComputerAction(
            actionID: "messages.send",
            arguments: [
                "recipient": "+15551234567",
                "body": "Hello",
            ],
            threadID: UUID(),
            projectID: UUID()
        )

        model.confirmPendingComputerActionPreview()

        try await eventually(timeoutSeconds: 1.0) {
            model.permissionRecoveryNotice?.target == .automation
        }
    }

    func testAppleScriptRunUsesEveryRunPromptWithoutPersistence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-script-permission-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let dbURL = root.appendingPathComponent("metadata.sqlite", isDirectory: false)
        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)
        let registry = ComputerActionRegistry(appleScriptRun: AppleScriptRunAction(runner: FixedScriptRunner()))
        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            computerActionRegistry: registry
        )

        var promptCount = 0
        model.computerActionPermissionPromptHandler = { _, _ in
            promptCount += 1
            return true
        }

        let projectURL = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let project = try await repositories.projectRepository.createProject(
            named: "Script Test",
            path: projectURL.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let thread = try await repositories.threadRepository.createThread(
            projectID: project.id,
            title: "Script Thread"
        )
        let arguments = [
            "language": "applescript",
            "script": "on run argv\nreturn \"ok\"\nend run",
            "argumentsJson": "[]",
        ]

        for _ in 0 ..< 2 {
            try await model.runNativeComputerAction(
                actionID: "apple.script.run",
                arguments: arguments,
                threadID: thread.id,
                projectID: project.id
            )

            XCTAssertNotNil(model.pendingComputerActionPreview)
            model.confirmPendingComputerActionPreview()
            try await eventually(timeoutSeconds: 1.0) {
                model.pendingComputerActionPreview == nil
                    && model.isComputerActionExecutionInProgress == false
            }
        }

        XCTAssertEqual(promptCount, 2)
        let storedDecision = try await repositories.computerActionPermissionRepository.get(
            actionID: "apple.script.run",
            projectID: project.id
        )
        XCTAssertNil(storedDecision)
        XCTAssertTrue(model.requiresPerRunComputerActionPermissionPrompt(actionID: "apple.script.run"))
        XCTAssertFalse(model.shouldPersistComputerActionPermissionDecision(actionID: "apple.script.run"))
    }

    private func eventually(
        timeoutSeconds: TimeInterval,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Condition not met within \(timeoutSeconds) seconds")
    }
}

private struct PermissionDeniedCalendarSource: CalendarEventSource {
    func events(from _: Date, to _: Date) async throws -> [CalendarEvent] {
        throw ComputerActionError.permissionDenied(
            "Calendar access is denied. Enable Calendar permissions in System Settings > Privacy & Security > Calendars."
        )
    }
}

private actor PermissionDeniedMessagesSender: MessagesSender {
    func send(message _: String, to _: String) async throws {
        throw ComputerActionError.permissionDenied(
            "Messages send failed. Check Messages permissions in System Settings > Privacy & Security > Automation."
        )
    }
}

private struct FixedScriptRunner: OsaScriptCommandRunning {
    func run(
        language _: OsaScriptLanguage,
        script _: String,
        arguments _: [String]
    ) async throws -> String {
        "ok"
    }
}
