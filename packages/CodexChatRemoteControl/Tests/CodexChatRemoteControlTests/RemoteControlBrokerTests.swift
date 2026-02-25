@testable import CodexChatRemoteControl
import Foundation
import XCTest

private actor RecordingRelayRegistrar: RemoteControlRelayRegistering {
    private(set) var requests: [RemoteControlPairStartRequest] = []

    func startPairing(_ request: RemoteControlPairStartRequest) async throws -> RemoteControlPairStartResponse {
        requests.append(request)
        return RemoteControlPairStartResponse(accepted: true)
    }

    func latestRequest() -> RemoteControlPairStartRequest? {
        requests.last
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

        let firstConsumeResult = await broker.consumeJoinToken(descriptor.joinTokenLease.token)
        let secondConsumeResult = await broker.consumeJoinToken(descriptor.joinTokenLease.token)
        XCTAssertTrue(firstConsumeResult)
        XCTAssertFalse(secondConsumeResult)

        let status = await broker.currentStatus()
        XCTAssertEqual(status.phase, .active)
    }

    func testStopSessionTransitionsToDisconnected() async throws {
        let broker = RemoteControlBroker()
        try await broker.startSession(
            joinBaseURL: XCTUnwrap(URL(string: "https://remote.codexchat.example/rc")),
            relayWebSocketURL: XCTUnwrap(URL(string: "wss://relay.codexchat.example/ws"))
        )

        await broker.stopSession(reason: "Stopped by test")

        let status = await broker.currentStatus()
        XCTAssertEqual(status.phase, .disconnected)
        XCTAssertEqual(status.disconnectReason, "Stopped by test")
        XCTAssertNil(status.session)
    }
}
