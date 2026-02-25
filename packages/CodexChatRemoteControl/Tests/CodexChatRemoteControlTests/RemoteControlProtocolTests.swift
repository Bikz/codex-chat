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

    func testEnvelopeRoundTripForEventPayloadWithMessageMetadata() throws {
        let original = RemoteControlEnvelope(
            sessionID: "session-1",
            seq: 9,
            timestamp: Date(timeIntervalSince1970: 1_700_000_300),
            payload: .event(
                RemoteControlEventPayload(
                    name: "thread.message.append",
                    threadID: "thread-1",
                    body: "Streaming update",
                    messageID: "message-1",
                    role: "assistant",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_301)
                )
            )
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteControlEnvelope.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testEnvelopeDecodesLegacyEventPayloadWithoutOptionalMessageMetadata() throws {
        let rawJSON = """
        {
          "schemaVersion": 1,
          "sessionID": "session-1",
          "seq": 10,
          "timestamp": "2023-11-14T22:18:20Z",
          "payload": {
            "type": "event",
            "payload": {
              "name": "thread.message.append",
              "threadID": "thread-1",
              "body": "Legacy event"
            }
          }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RemoteControlEnvelope.self, from: Data(rawJSON.utf8))

        guard case let .event(payload) = decoded.payload else {
            XCTFail("Expected event payload")
            return
        }

        XCTAssertEqual(payload.name, "thread.message.append")
        XCTAssertEqual(payload.threadID, "thread-1")
        XCTAssertEqual(payload.body, "Legacy event")
        XCTAssertNil(payload.messageID)
        XCTAssertNil(payload.role)
        XCTAssertNil(payload.createdAt)
    }
}
