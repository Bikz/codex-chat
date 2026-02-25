@testable import CodexChatRemoteControl
import Foundation
import XCTest

final class RemoteControlProtocolTests: XCTestCase {
    func testEnvelopeRoundTripForCommandPayload() throws {
        let original = RemoteControlEnvelope(
            sessionID: "session-1",
            seq: 42,
            timestamp: Date(timeIntervalSince1970: 1_700_000_100),
            payload: .command(
                RemoteControlCommandPayload(
                    name: .threadSendMessage,
                    threadID: "thread-1",
                    projectID: "project-1",
                    text: "Run tests"
                )
            )
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteControlEnvelope.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.schemaVersion, RemoteControlProtocol.schemaVersion)
    }

    func testEnvelopeRoundTripForSnapshotPayload() throws {
        let snapshot = RemoteControlSnapshotPayload(
            projects: [.init(id: "project-1", name: "General")],
            threads: [.init(id: "thread-1", projectID: "project-1", title: "Intro", isPinned: false)],
            selectedProjectID: "project-1",
            selectedThreadID: "thread-1",
            messages: [
                .init(
                    id: "message-1",
                    threadID: "thread-1",
                    role: "user",
                    text: "Hello",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_200)
                ),
            ],
            turnState: .init(threadID: "thread-1", isTurnInProgress: true, isAwaitingApproval: false),
            pendingApprovals: []
        )

        let original = RemoteControlEnvelope(
            sessionID: "session-1",
            seq: 1,
            payload: .snapshot(snapshot)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteControlEnvelope.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }
}
