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

        let third = model.adaptiveIntent(for: "whats on my cal tmrw?")
        XCTAssertEqual(third, .calendarToday(rangeHours: 24))
    }

    func testAdaptiveIntentParsesRemindersCheckPhrases() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let first = model.adaptiveIntent(for: "Can you check my reminders today?")
        XCTAssertEqual(first, .remindersToday(rangeHours: 24))

        let second = model.adaptiveIntent(for: "show reminders for the next 6 hours")
        XCTAssertEqual(second, .remindersToday(rangeHours: 6))
    }

    func testAdaptiveIntentUsesCalendarContextForFollowUpQueries() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        model.selectedThreadID = threadID
        model.transcriptStore[threadID] = [
            .message(
                ChatMessage(
                    threadId: threadID,
                    role: .user,
                    text: "What's on my calendar today?"
                )
            ),
        ]

        let tomorrowIntent = model.adaptiveIntent(for: "tomorrow?")
        XCTAssertEqual(tomorrowIntent, .calendarToday(rangeHours: 24))

        let rangeIntent = model.adaptiveIntent(for: "next 8 hours")
        XCTAssertEqual(rangeIntent, .calendarToday(rangeHours: 8))
    }

    func testAdaptiveIntentUsesRemindersContextForFollowUpQueries() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        model.selectedThreadID = threadID
        model.transcriptStore[threadID] = [
            .message(
                ChatMessage(
                    threadId: threadID,
                    role: .user,
                    text: "What reminders do I have today?"
                )
            ),
        ]

        let tomorrowIntent = model.adaptiveIntent(for: "tmrw?")
        XCTAssertEqual(tomorrowIntent, .remindersToday(rangeHours: 24))

        let rangeIntent = model.adaptiveIntent(for: "in 3 hours")
        XCTAssertEqual(rangeIntent, .remindersToday(rangeHours: 3))
    }

    func testAdaptiveIntentParsesExpandedMessageSendPhrases() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let first = model.adaptiveIntent(for: "send an iMessage to +16502509815 saying hello from codex")
        XCTAssertEqual(
            first,
            .messagesSend(recipient: "+16502509815", body: "hello from codex")
        )

        let second = model.adaptiveIntent(for: "Can you send message to Alice: Running 5 min late.")
        XCTAssertEqual(
            second,
            .messagesSend(recipient: "Alice", body: "Running 5 min late.")
        )

        let third = model.adaptiveIntent(for: "please text \"Bob\" saying \"Hey there\"")
        XCTAssertEqual(
            third,
            .messagesSend(recipient: "Bob", body: "Hey there")
        )
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

    func testCalendarActionAppendsVisibleTranscriptEntries() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1800)
        let event = CalendarEvent(
            id: "event-1",
            title: "Standup",
            calendarName: "Work",
            startAt: start,
            endAt: end,
            isAllDay: false
        )

        let calendarAction = CalendarTodayAction(
            eventSource: FixedCalendarEventSource(events: [event]),
            nowProvider: { start }
        )
        let registry = ComputerActionRegistry(calendarToday: calendarAction)
        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil,
            computerActionRegistry: registry
        )

        let threadID = UUID()
        try await model.runNativeComputerAction(
            actionID: "calendar.today",
            arguments: ["rangeHours": "24"],
            threadID: threadID,
            projectID: UUID()
        )

        guard let entries = model.transcriptStore[threadID] else {
            XCTFail("Expected transcript entries for calendar action")
            return
        }

        XCTAssertEqual(entries.count, 3)

        guard case let .message(userMessage) = entries[0] else {
            XCTFail("Expected user message as first transcript entry")
            return
        }
        XCTAssertEqual(userMessage.role, .user)
        XCTAssertEqual(userMessage.text, "What's on my calendar today?")

        guard case let .actionCard(actionCard) = entries[1] else {
            XCTFail("Expected action card as second transcript entry")
            return
        }
        XCTAssertEqual(actionCard.method, "computer_action/execute")

        guard case let .message(assistantMessage) = entries[2] else {
            XCTFail("Expected assistant message as third transcript entry")
            return
        }
        XCTAssertEqual(assistantMessage.role, .assistant)
        XCTAssertTrue(assistantMessage.text.contains("Standup"))
    }

    func testCalendarActionPersistsTranscriptForRehydration() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-calendar-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let dbURL = root.appendingPathComponent("metadata.sqlite", isDirectory: false)
        let database = try MetadataDatabase(databaseURL: dbURL)
        let repositories = MetadataRepositories(database: database)

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1800)
        let event = CalendarEvent(
            id: "event-2",
            title: "Planning",
            calendarName: "Work",
            startAt: start,
            endAt: end,
            isAllDay: false
        )
        let calendarAction = CalendarTodayAction(
            eventSource: FixedCalendarEventSource(events: [event]),
            nowProvider: { start }
        )
        let registry = ComputerActionRegistry(calendarToday: calendarAction)
        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            computerActionRegistry: registry
        )

        let projectURL = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let project = try await repositories.projectRepository.createProject(
            named: "Calendar Test",
            path: projectURL.path,
            trustState: .trusted,
            isGeneralProject: false
        )
        let thread = try await repositories.threadRepository.createThread(
            projectID: project.id,
            title: "Calendar thread"
        )

        try await model.runNativeComputerAction(
            actionID: "calendar.today",
            arguments: ["rangeHours": "24"],
            threadID: thread.id,
            projectID: project.id
        )

        model.transcriptStore[thread.id] = []
        await model.rehydrateThreadTranscript(threadID: thread.id)

        guard let entries = model.transcriptStore[thread.id] else {
            XCTFail("Expected rehydrated entries for calendar action")
            return
        }

        XCTAssertGreaterThanOrEqual(entries.count, 3)
        let userMessages = entries.compactMap { entry -> ChatMessage? in
            guard case let .message(message) = entry, message.role == .user else {
                return nil
            }
            return message
        }
        let assistantMessages = entries.compactMap { entry -> ChatMessage? in
            guard case let .message(message) = entry, message.role == .assistant else {
                return nil
            }
            return message
        }

        XCTAssertTrue(userMessages.contains(where: { $0.text.contains("calendar") }))
        XCTAssertTrue(assistantMessages.contains(where: { $0.text.contains("Planning") }))
    }

    func testCalendarActionUsesTomorrowPromptWhenDayOffsetProvided() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let event = CalendarEvent(
            id: "event-3",
            title: "Offsite",
            calendarName: "Work",
            startAt: start.addingTimeInterval(86400),
            endAt: start.addingTimeInterval(90000),
            isAllDay: false
        )

        let calendarAction = CalendarTodayAction(
            eventSource: FixedCalendarEventSource(events: [event]),
            nowProvider: { start }
        )
        let registry = ComputerActionRegistry(calendarToday: calendarAction)
        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil,
            computerActionRegistry: registry
        )

        let threadID = UUID()
        try await model.runNativeComputerAction(
            actionID: "calendar.today",
            arguments: [
                "rangeHours": "24",
                "dayOffset": "1",
                "anchor": "dayStart",
            ],
            threadID: threadID,
            projectID: UUID()
        )

        guard let entries = model.transcriptStore[threadID] else {
            XCTFail("Expected transcript entries for calendar action")
            return
        }

        guard case let .message(userMessage) = entries.first else {
            XCTFail("Expected first transcript entry to be a user message")
            return
        }
        XCTAssertEqual(userMessage.text, "What's on my calendar tomorrow?")
    }

    func testCalendarActionUsesOriginalQueryTextWhenProvided() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let event = CalendarEvent(
            id: "event-4",
            title: "Demo",
            calendarName: "Work",
            startAt: start,
            endAt: start.addingTimeInterval(1800),
            isAllDay: false
        )

        let calendarAction = CalendarTodayAction(
            eventSource: FixedCalendarEventSource(events: [event]),
            nowProvider: { start }
        )
        let registry = ComputerActionRegistry(calendarToday: calendarAction)
        let model = AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil,
            computerActionRegistry: registry
        )

        let threadID = UUID()
        try await model.runNativeComputerAction(
            actionID: "calendar.today",
            arguments: [
                "rangeHours": "24",
                "queryText": "whats on my cal tmrw?",
                "dayOffset": "1",
                "anchor": "dayStart",
            ],
            threadID: threadID,
            projectID: UUID()
        )

        guard let entries = model.transcriptStore[threadID],
              case let .message(userMessage) = entries.first
        else {
            XCTFail("Expected first transcript entry to be a user message")
            return
        }

        XCTAssertEqual(userMessage.text, "whats on my cal tmrw?")
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

private struct FixedCalendarEventSource: CalendarEventSource {
    let events: [CalendarEvent]

    func events(from _: Date, to _: Date) async throws -> [CalendarEvent] {
        events
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
