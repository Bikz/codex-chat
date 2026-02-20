@testable import CodexComputerActions
import XCTest

final class MessagesSendActionErrorMappingTests: XCTestCase {
    func testExecuteNormalizesPermissionDeniedExecutionFailures() async throws {
        let action = MessagesSendAction(
            sender: ThrowingMessagesSender(
                error: ComputerActionError.executionFailed("Not authorized to send Apple events to Messages. (-1743)")
            )
        )

        let request = ComputerActionRequest(
            runContextID: "msg-permission",
            arguments: [
                "recipient": "+15551234567",
                "body": "Hello",
            ]
        )

        let preview = try await action.preview(request: request)

        do {
            _ = try await action.execute(request: request, preview: preview)
            XCTFail("Expected permission denied error")
        } catch let error as ComputerActionError {
            guard case let .permissionDenied(message) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertTrue(message.lowercased().contains("automation"))
        }
    }

    func testExecutePreservesNonPermissionExecutionFailures() async throws {
        let action = MessagesSendAction(
            sender: ThrowingMessagesSender(
                error: ComputerActionError.executionFailed("Could not resolve recipient '+15551234567' in Messages.")
            )
        )

        let request = ComputerActionRequest(
            runContextID: "msg-invalid-recipient",
            arguments: [
                "recipient": "+15551234567",
                "body": "Hello",
            ]
        )

        let preview = try await action.preview(request: request)

        do {
            _ = try await action.execute(request: request, preview: preview)
            XCTFail("Expected execution failure")
        } catch let error as ComputerActionError {
            guard case let .executionFailed(message) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertTrue(message.contains("Could not resolve recipient"))
        }
    }
}

private actor ThrowingMessagesSender: MessagesSender {
    let error: ComputerActionError

    init(error: ComputerActionError) {
        self.error = error
    }

    func send(message _: String, to _: String) async throws {
        throw error
    }
}
