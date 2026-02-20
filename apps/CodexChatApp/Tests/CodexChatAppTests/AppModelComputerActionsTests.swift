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
