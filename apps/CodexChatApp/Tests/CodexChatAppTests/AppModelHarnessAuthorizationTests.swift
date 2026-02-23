@testable import CodexChatShared
import XCTest

@MainActor
final class AppModelHarnessAuthorizationTests: XCTestCase {
    func testHandleHarnessInvokeRejectsUnsupportedProtocol() async {
        let model = makeModel()
        let runToken = model.registerHarnessRunContext(threadID: UUID(), projectID: UUID())

        let response = await model.handleHarnessInvokeRequest(
            HarnessInvokeRequest(
                protocolVersion: 999,
                requestID: "req-1",
                sessionToken: "session-token",
                runToken: runToken,
                actionID: "calendar.today",
                argumentsJson: "{}"
            )
        )

        XCTAssertEqual(response.status, .invalid)
        XCTAssertEqual(response.errorCode, "unsupported_protocol")
    }

    func testHandleHarnessInvokeRejectsInvalidSessionToken() async {
        let model = makeModel()
        let runToken = model.registerHarnessRunContext(threadID: UUID(), projectID: UUID())

        let response = await model.handleHarnessInvokeRequest(
            HarnessInvokeRequest(
                protocolVersion: 1,
                requestID: "req-2",
                sessionToken: "wrong",
                runToken: runToken,
                actionID: "calendar.today",
                argumentsJson: "{}"
            )
        )

        XCTAssertEqual(response.status, .unauthorized)
        XCTAssertEqual(response.errorCode, "invalid_session_token")
    }

    func testHandleHarnessInvokeRejectsInvalidRunToken() async {
        let model = makeModel()

        let response = await model.handleHarnessInvokeRequest(
            HarnessInvokeRequest(
                protocolVersion: 1,
                requestID: "req-3",
                sessionToken: "session-token",
                runToken: "missing-token",
                actionID: "calendar.today",
                argumentsJson: "{}"
            )
        )

        XCTAssertEqual(response.status, .unauthorized)
        XCTAssertEqual(response.errorCode, "invalid_run_token")
    }

    func testHandleHarnessInvokeRejectsOversizedArguments() async {
        let model = makeModel()
        let runToken = model.registerHarnessRunContext(threadID: UUID(), projectID: UUID())

        let response = await model.handleHarnessInvokeRequest(
            HarnessInvokeRequest(
                protocolVersion: 1,
                requestID: "req-4",
                sessionToken: "session-token",
                runToken: runToken,
                actionID: "calendar.today",
                argumentsJson: String(repeating: "a", count: (64 * 1024) + 1)
            )
        )

        XCTAssertEqual(response.status, .invalid)
        XCTAssertEqual(response.errorCode, "arguments_too_large")
    }

    private func makeModel() -> AppModel {
        AppModel(
            repositories: nil,
            runtime: nil,
            bootError: nil,
            voiceCaptureService: StubVoiceCaptureService(),
            harnessEnvironment: ComputerActionHarnessEnvironment(
                socketPath: "/tmp/codexchat-harness-tests.sock",
                sessionToken: "session-token",
                wrapperPath: "/tmp/codexchat-action"
            )
        )
    }
}

private final class StubVoiceCaptureService: VoiceCaptureService, @unchecked Sendable {
    func requestAuthorization() async -> VoiceCaptureAuthorizationStatus {
        .authorized
    }

    func startCapture() async throws {}
    func stopCapture() async throws -> String {
        ""
    }

    func cancelCapture() async {}
}
