@testable import CodexKit
import XCTest

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
                "delta": .string("Hello"),
            ])
        )

        let deltaEvents = AppServerEventDecoder.decodeAll(deltaNotification)
        guard case let .assistantMessageDelta(itemID, delta)? = deltaEvents.first else {
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
                    "status": .string("completed"),
                ]),
            ])
        )

        let completionEvents = AppServerEventDecoder.decodeAll(completionNotification)
        guard case let .turnCompleted(completion)? = completionEvents.first else {
            XCTFail("Expected turnCompleted")
            return
        }
        XCTAssertEqual(completion.turnID, "turn_1")
        XCTAssertEqual(completion.status, "completed")
    }

    func testEventDecoderAccountNotifications() {
        let updated = JSONRPCMessageEnvelope.notification(
            method: "account/updated",
            params: .object(["authMode": .string("chatgpt")])
        )
        guard case let .accountUpdated(mode)? = AppServerEventDecoder.decodeAll(updated).first else {
            XCTFail("Expected accountUpdated")
            return
        }
        XCTAssertEqual(mode, .chatGPT)

        let completed = JSONRPCMessageEnvelope.notification(
            method: "account/login/completed",
            params: .object([
                "loginId": .string("login_123"),
                "success": .bool(true),
                "error": .null,
            ])
        )
        guard case let .accountLoginCompleted(completion)? = AppServerEventDecoder.decodeAll(completed).first else {
            XCTFail("Expected accountLoginCompleted")
            return
        }
        XCTAssertEqual(completion.loginID, "login_123")
        XCTAssertTrue(completion.success)
        XCTAssertNil(completion.error)
    }

    func testEventDecoderCommandOutputAndFileChanges() {
        let commandOutput = JSONRPCMessageEnvelope.notification(
            method: "item/commandExecution/outputDelta",
            params: .object([
                "threadId": .string("thr_1"),
                "turnId": .string("turn_1"),
                "itemId": .string("item_cmd_1"),
                "delta": .string("stdout line"),
            ])
        )
        let commandEvents = AppServerEventDecoder.decodeAll(commandOutput)
        guard case let .commandOutputDelta(output)? = commandEvents.first else {
            XCTFail("Expected command output delta")
            return
        }
        XCTAssertEqual(output.itemID, "item_cmd_1")
        XCTAssertEqual(output.threadID, "thr_1")
        XCTAssertEqual(output.turnID, "turn_1")
        XCTAssertEqual(output.delta, "stdout line")

        let fileChangeStarted = JSONRPCMessageEnvelope.notification(
            method: "item/started",
            params: .object([
                "threadId": .string("thr_1"),
                "turnId": .string("turn_1"),
                "item": .object([
                    "id": .string("item_file_1"),
                    "type": .string("fileChange"),
                    "status": .string("inProgress"),
                    "changes": .array([
                        .object([
                            "path": .string("README.md"),
                            "kind": .string("update"),
                            "diff": .string("@@ -1 +1 @@"),
                        ]),
                    ]),
                ]),
            ])
        )

        let fileEvents = AppServerEventDecoder.decodeAll(fileChangeStarted)
        XCTAssertEqual(fileEvents.count, 2)

        let updateEvent = fileEvents.first {
            if case .fileChangesUpdated = $0 { return true }
            return false
        }
        guard case let .fileChangesUpdated(update)? = updateEvent else {
            XCTFail("Expected fileChangesUpdated")
            return
        }
        XCTAssertEqual(update.itemID, "item_file_1")
        XCTAssertEqual(update.threadID, "thr_1")
        XCTAssertEqual(update.changes.count, 1)
        XCTAssertEqual(update.changes.first?.path, "README.md")
    }
}
