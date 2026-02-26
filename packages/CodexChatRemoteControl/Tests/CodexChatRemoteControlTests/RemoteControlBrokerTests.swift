@testable import CodexChatRemoteControl
import Foundation
import XCTest

private actor RecordingRelayRegistrar: RemoteControlRelayRegistering {
    private(set) var requests: [RemoteControlPairStartRequest] = []
    private(set) var stopRequests: [RemoteControlPairStopRequest] = []

    func startPairing(_ request: RemoteControlPairStartRequest) async throws -> RemoteControlPairStartResponse {
        requests.append(request)
        return RemoteControlPairStartResponse(accepted: true)
    }

    func latestRequest() -> RemoteControlPairStartRequest? {
        requests.last
    }

    func stopPairing(_ request: RemoteControlPairStopRequest) async throws -> RemoteControlPairStopResponse {
        stopRequests.append(request)
        return RemoteControlPairStopResponse(accepted: true)
    }

    func latestStopRequest() -> RemoteControlPairStopRequest? {
        stopRequests.last
    }
}

private struct StaticRandomSource: RemoteControlRandomDataSource {
    func randomData(count: Int) throws -> Data {
        Data(repeating: 7, count: count)
    }
}

final class RemoteControlBrokerTests: XCTestCase {
    func testStartSessionRegistersPairAndJoinTokenIsSingleUse() async throws {
        let registrar = RecordingRelayRegistrar()
        let tokenFactory = RemoteControlTokenFactory(
            dateProvider: SystemRemoteControlDateProvider(),
            randomDataSource: StaticRandomSource()
        )
        let broker = RemoteControlBroker(relayRegistrar: registrar, tokenFactory: tokenFactory)

        let descriptor = try await broker.startSession(
            joinBaseURL: XCTUnwrap(URL(string: "https://remote.codexchat.example/rc")),
            relayWebSocketURL: XCTUnwrap(URL(string: "wss://relay.codexchat.example/ws")),
            policy: RemoteControlPairingSecurityPolicy(joinTokenTTL: 120, idleTimeout: 60)
        )

        let request = await registrar.latestRequest()
        XCTAssertEqual(request?.sessionID, descriptor.sessionID)
        XCTAssertEqual(request?.desktopSessionToken, descriptor.desktopSessionToken)
        XCTAssertEqual(request?.relayWebSocketURL, "wss://relay.codexchat.example/ws")

        let firstConsumeResult = await broker.consumeJoinToken(descriptor.joinTokenLease.token)
        let secondConsumeResult = await broker.consumeJoinToken(descriptor.joinTokenLease.token)
        XCTAssertTrue(firstConsumeResult)
        XCTAssertFalse(secondConsumeResult)

        let status = await broker.currentStatus()
        XCTAssertEqual(status.phase, .active)
    }

    func testStopSessionTransitionsToDisconnected() async throws {
        let registrar = RecordingRelayRegistrar()
        let broker = RemoteControlBroker(relayRegistrar: registrar)
        let descriptor = try await broker.startSession(
            joinBaseURL: XCTUnwrap(URL(string: "https://remote.codexchat.example/rc")),
            relayWebSocketURL: XCTUnwrap(URL(string: "wss://relay.codexchat.example/ws"))
        )

        await broker.stopSession(reason: "Stopped by test")

        let stopRequest = await registrar.latestStopRequest()
        XCTAssertEqual(stopRequest?.sessionID, descriptor.sessionID)
        XCTAssertEqual(stopRequest?.relayWebSocketURL, descriptor.relayWebSocketURL.absoluteString)
        XCTAssertEqual(stopRequest?.desktopSessionToken, descriptor.desktopSessionToken)

        let status = await broker.currentStatus()
        XCTAssertEqual(status.phase, .disconnected)
        XCTAssertEqual(status.disconnectReason, "Stopped by test")
        XCTAssertNil(status.session)
    }
}
