import XCTest
@testable import CodexKit

final class CodexKitTests: XCTestCase {
    func testJSONLFramerFramesCompleteLinesAcrossChunks() throws {
        var framer = JSONLFramer()
        let first = try framer.append(Data("{\"method\":\"turn/started\"}".utf8))
        XCTAssertTrue(first.isEmpty)

        let second = try framer.append(Data("\n{\"method\":\"turn/completed\"}\n".utf8))
        XCTAssertEqual(second.count, 2)
        let decoder = JSONDecoder()
        let started = try decoder.decode(JSONRPCMessageEnvelope.self, from: second[0])
        let completed = try decoder.decode(JSONRPCMessageEnvelope.self, from: second[1])
        XCTAssertEqual(started.method, "turn/started")
        XCTAssertEqual(completed.method, "turn/completed")
    }

    func testRequestCorrelatorResolvesMatchingResponse() async throws {
        let correlator = RequestCorrelator()
        let requestID = await correlator.makeRequestID()

        let waiter = Task {
            try await correlator.suspendResponse(id: requestID)
        }
        await Task.yield()

        let response = JSONRPCMessageEnvelope.response(
            id: requestID,
            result: .object(["ok": .bool(true)])
        )
        _ = await correlator.resolveResponse(response)

        let resolved = try await waiter.value
        XCTAssertEqual(resolved.id, requestID)
        XCTAssertEqual(resolved.result?.value(at: ["ok"])?.boolValue, true)
    }

    func testEventDecoderAgentDeltaAndTurnCompletion() {
        let deltaNotification = JSONRPCMessageEnvelope.notification(
            method: "item/agentMessage/delta",
            params: .object([
                "itemId": .string("item_1"),
                "delta": .string("Hello")
            ])
        )

        guard case .assistantMessageDelta(let itemID, let delta)? = AppServerEventDecoder.decode(deltaNotification) else {
            XCTFail("Expected assistantMessageDelta")
            return
        }
        XCTAssertEqual(itemID, "item_1")
        XCTAssertEqual(delta, "Hello")

        let completionNotification = JSONRPCMessageEnvelope.notification(
            method: "turn/completed",
            params: .object([
                "turn": .object([
                    "id": .string("turn_1"),
                    "status": .string("completed")
                ])
            ])
        )

        guard case .turnCompleted(let completion)? = AppServerEventDecoder.decode(completionNotification) else {
            XCTFail("Expected turnCompleted")
            return
        }
        XCTAssertEqual(completion.turnID, "turn_1")
        XCTAssertEqual(completion.status, "completed")
    }
}
