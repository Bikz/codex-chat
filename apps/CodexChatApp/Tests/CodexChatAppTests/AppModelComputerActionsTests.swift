import CodexChatCore
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

    func testPermissionRecoveryTargetIgnoresAppLevelDeny() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let target = model.permissionRecoveryTargetForComputerAction(
            actionID: "messages.send",
            error: .permissionDenied("Permission denied for Messages Send.")
        )

        XCTAssertNil(target)
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
