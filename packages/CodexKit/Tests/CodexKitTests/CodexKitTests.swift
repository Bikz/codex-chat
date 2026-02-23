@testable import CodexKit
import XCTest

final class CodexKitTests: XCTestCase {
    func testRuntimeAccountSummaryNameSupportsInitAndDecoding() throws {
        let named = RuntimeAccountSummary(type: "chatgpt", name: "Bikram Brar", email: "bikram@example.com", planType: "pro")
        XCTAssertEqual(named.name, "Bikram Brar")

        let encoded = try JSONEncoder().encode(named)
        let decodedNamed = try JSONDecoder().decode(RuntimeAccountSummary.self, from: encoded)
        XCTAssertEqual(decodedNamed.name, "Bikram Brar")
    }

    func testDecodeModelListParsesDisplayNamesAndReasoningEfforts() throws {
        let payload: JSONValue = .object([
            "data": .array([
                .object([
                    "id": .string("gpt-5.3-codex"),
                    "model": .string("gpt-5.3-codex"),
                    "displayName": .string("GPT-5.3 Codex"),
                    "description": .string("Frontier coding model"),
                    "supportedReasoningEfforts": .array([
                        .object([
                            "reasoningEffort": .string("low"),
                            "description": .string("Fast responses"),
                        ]),
                        .object([
                            "reasoningEffort": .string("xhigh"),
                            "description": .string("Deep reasoning"),
                        ]),
                    ]),
                    "defaultReasoningEffort": .string("medium"),
                    "supportedWebSearchModes": .array([
                        .string("disabled"),
                        .string("cached"),
                    ]),
                    "defaultWebSearchMode": .string("cached"),
                    "isDefault": .bool(true),
                    "upgrade": .null,
                ]),
            ]),
            "nextCursor": .string("cursor_2"),
        ])

        let decoded = try CodexRuntime.decodeModelList(from: payload)
        XCTAssertEqual(decoded.models.count, 1)
        XCTAssertEqual(decoded.nextCursor, "cursor_2")

        let first = try XCTUnwrap(decoded.models.first)
        XCTAssertEqual(first.id, "gpt-5.3-codex")
        XCTAssertEqual(first.displayName, "GPT-5.3 Codex")
        XCTAssertEqual(first.defaultReasoningEffort, "medium")
        XCTAssertTrue(first.isDefault)
        XCTAssertEqual(first.supportedReasoningEfforts.map(\.reasoningEffort), ["low", "xhigh"])
        XCTAssertEqual(first.supportedWebSearchModes, [.disabled, .cached])
        XCTAssertEqual(first.defaultWebSearchMode, .cached)
    }

    func testDecodeModelListRejectsMissingDataArray() {
        let payload: JSONValue = .object([:])

        XCTAssertThrowsError(try CodexRuntime.decodeModelList(from: payload)) { error in
            guard case let CodexRuntimeError.invalidResponse(message) = error else {
                XCTFail("Expected invalidResponse, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("model/list"))
        }
    }

    func testMergedEnvironmentPrefersOverrides() {
        let base = ["PATH": "/usr/bin", "HOME": "/Users/base"]
        let overrides = ["HOME": "/Users/override", "CODEX_HOME": "/tmp/codex-home"]

        let merged = CodexRuntime.mergedEnvironment(base: base, overrides: overrides)
        XCTAssertEqual(merged["PATH"], "/usr/bin")
        XCTAssertEqual(merged["HOME"], "/Users/override")
        XCTAssertEqual(merged["CODEX_HOME"], "/tmp/codex-home")
    }

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

    func testJSONLFramerStripsCarriageReturnForCRLF() throws {
        var framer = JSONLFramer()
        let frames = try framer.append(Data("{\"method\":\"turn/started\"}\r\n".utf8))
        XCTAssertEqual(frames.count, 1)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JSONRPCMessageEnvelope.self, from: frames[0])
        XCTAssertEqual(decoded.method, "turn/started")
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
        XCTAssertEqual(resolved.id, .int(requestID))
        XCTAssertEqual(resolved.result?.value(at: ["ok"])?.boolValue, true)
    }

    func testRequestCorrelatorBuffersEarlyResponseBeforeSuspending() async throws {
        let correlator = RequestCorrelator()
        let requestID = await correlator.makeRequestID()

        let response = JSONRPCMessageEnvelope.response(
            id: requestID,
            result: .object(["ok": .bool(true)])
        )
        _ = await correlator.resolveResponse(response)

        let resolved = try await correlator.suspendResponse(id: requestID)
        XCTAssertEqual(resolved.id, .int(requestID))
        XCTAssertEqual(resolved.result?.value(at: ["ok"])?.boolValue, true)
    }

    func testRequestCorrelatorAcceptsNumericStringResponseID() async throws {
        let correlator = RequestCorrelator()
        let requestID = await correlator.makeRequestID()

        let response = JSONRPCMessageEnvelope(
            id: .string(String(requestID)),
            method: nil,
            params: nil,
            result: .object(["ok": .bool(true)]),
            error: nil
        )
        _ = await correlator.resolveResponse(response)

        let resolved = try await correlator.suspendResponse(id: requestID)
        XCTAssertEqual(resolved.id, .string(String(requestID)))
        XCTAssertEqual(resolved.result?.value(at: ["ok"])?.boolValue, true)
    }

    func testRequestCorrelatorFailsSuspensionAfterFailAllEvenIfNotPending() async throws {
        let correlator = RequestCorrelator()
        let requestID = await correlator.makeRequestID()

        await correlator.failAll(error: CodexRuntimeError.transportClosed)

        do {
            _ = try await correlator.suspendResponse(id: requestID)
            XCTFail("Expected suspendResponse to throw after failAll")
        } catch {
            guard let runtimeError = error as? CodexRuntimeError else {
                XCTFail("Expected CodexRuntimeError, got: \(type(of: error))")
                return
            }
            XCTAssertEqual(runtimeError.errorDescription, CodexRuntimeError.transportClosed.errorDescription)
        }

        await correlator.resetTransport()

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
        guard case let .assistantMessageDelta(threadID, turnID, itemID, delta)? = deltaEvents.first else {
            XCTFail("Expected assistantMessageDelta")
            return
        }
        XCTAssertNil(threadID)
        XCTAssertNil(turnID)
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

    func testEventDecoderPreservesThreadAndTurnMetadataWhenPresent() {
        let deltaNotification = JSONRPCMessageEnvelope.notification(
            method: "item/agentMessage/delta",
            params: .object([
                "threadId": .string("thr_123"),
                "turnId": .string("turn_abc"),
                "itemId": .string("item_9"),
                "delta": .string("Chunk"),
            ])
        )

        let deltaEvents = AppServerEventDecoder.decodeAll(deltaNotification)
        guard case let .assistantMessageDelta(threadID, turnID, itemID, delta)? = deltaEvents.first else {
            XCTFail("Expected assistantMessageDelta with thread metadata")
            return
        }
        XCTAssertEqual(threadID, "thr_123")
        XCTAssertEqual(turnID, "turn_abc")
        XCTAssertEqual(itemID, "item_9")
        XCTAssertEqual(delta, "Chunk")

        let completionNotification = JSONRPCMessageEnvelope.notification(
            method: "turn/completed",
            params: .object([
                "threadId": .string("thr_123"),
                "turn": .object([
                    "id": .string("turn_abc"),
                    "status": .string("completed"),
                ]),
            ])
        )

        let completionEvents = AppServerEventDecoder.decodeAll(completionNotification)
        guard case let .turnCompleted(completion)? = completionEvents.first else {
            XCTFail("Expected turnCompleted with thread metadata")
            return
        }
        XCTAssertEqual(completion.threadID, "thr_123")
        XCTAssertEqual(completion.turnID, "turn_abc")
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

    func testEventDecoderFollowUpSuggestions() {
        let suggestionEvent = JSONRPCMessageEnvelope.notification(
            method: "turn/followUpsSuggested",
            params: .object([
                "threadId": .string("thr_1"),
                "turnId": .string("turn_1"),
                "suggestions": .array([
                    .object([
                        "id": .string("s_1"),
                        "text": .string("Follow up on docs"),
                        "priority": .number(0),
                    ]),
                ]),
            ])
        )

        let events = AppServerEventDecoder.decodeAll(suggestionEvent)
        guard case let .followUpSuggestions(batch)? = events.first else {
            XCTFail("Expected followUpSuggestions")
            return
        }

        XCTAssertEqual(batch.threadID, "thr_1")
        XCTAssertEqual(batch.turnID, "turn_1")
        XCTAssertEqual(batch.suggestions.count, 1)
        XCTAssertEqual(batch.suggestions.first?.id, "s_1")
        XCTAssertEqual(batch.suggestions.first?.text, "Follow up on docs")
        XCTAssertEqual(batch.suggestions.first?.priority, 0)
    }

    func testEventDecoderParsesWorkerTraceMetadata() {
        let notification = JSONRPCMessageEnvelope.notification(
            method: "item/completed",
            params: .object([
                "threadId": .string("thr_worker"),
                "turnId": .string("turn_worker"),
                "item": .object([
                    "id": .string("item_worker_1"),
                    "type": .string("toolCall"),
                    "worker": .object([
                        "id": .string("worker-1"),
                        "role": .string("security_auditor"),
                        "prompt": .string("Audit auth paths."),
                        "output": .string("Found one missing check."),
                        "status": .string("completed"),
                    ]),
                ]),
            ])
        )

        let events = AppServerEventDecoder.decodeAll(notification)
        guard case let .action(action)? = events.first else {
            XCTFail("Expected action event")
            return
        }

        XCTAssertEqual(action.itemID, "item_worker_1")
        XCTAssertEqual(action.workerTrace?.workerID, "worker-1")
        XCTAssertEqual(action.workerTrace?.role, "security_auditor")
        XCTAssertEqual(action.workerTrace?.prompt, "Audit auth paths.")
        XCTAssertEqual(action.workerTrace?.output, "Found one missing check.")
        XCTAssertEqual(action.workerTrace?.status, "completed")
        XCTAssertNil(action.workerTrace?.unavailableReason)
    }

    func testJSONRPCMessageEnvelopeDecodesStringIDServerRequest() throws {
        let raw = #"{"id":"approval_req_1","method":"item/commandExecution/requestApproval","params":{"threadId":"thr_1"}}"#
        let decoded = try JSONDecoder().decode(JSONRPCMessageEnvelope.self, from: Data(raw.utf8))

        XCTAssertEqual(decoded.id, .string("approval_req_1"))
        XCTAssertEqual(decoded.method, "item/commandExecution/requestApproval")
        XCTAssertTrue(decoded.isServerRequest)
    }

    func testDecodeApprovalRequestSupportsSnakeCaseAndNestedIDs() {
        let request = CodexRuntime.decodeApprovalRequest(
            requestID: 99,
            method: "item/commandExecution/requestApproval",
            params: .object([
                "thread_id": .string("thr_snake"),
                "turn": .object([
                    "id": .string("turn_nested"),
                ]),
                "item": .object([
                    "id": .string("item_nested"),
                ]),
                "parsed_cmd": .array([
                    .string("git"),
                    .string("status"),
                ]),
                "working_directory": .string("/tmp/workspace"),
                "safety_risk": .string("medium"),
            ])
        )

        XCTAssertEqual(request.id, 99)
        XCTAssertEqual(request.threadID, "thr_snake")
        XCTAssertEqual(request.turnID, "turn_nested")
        XCTAssertEqual(request.itemID, "item_nested")
        XCTAssertEqual(request.command, ["git", "status"])
        XCTAssertEqual(request.cwd, "/tmp/workspace")
        XCTAssertEqual(request.risk, "medium")
    }

    func testEventDecoderAcceptsSnakeCaseThreadAndTurnIDs() {
        let notification = JSONRPCMessageEnvelope.notification(
            method: "turn/started",
            params: .object([
                "thread_id": .string("thr_snake"),
                "turn": .object([
                    "turn_id": .string("turn_snake"),
                    "id": .string("turn_snake"),
                ]),
            ])
        )

        let events = AppServerEventDecoder.decodeAll(notification)
        guard case let .turnStarted(threadID, turnID)? = events.first else {
            XCTFail("Expected turnStarted event")
            return
        }

        XCTAssertEqual(threadID, "thr_snake")
        XCTAssertEqual(turnID, "turn_snake")
    }

    func testEventDecoderWorkerTraceFallsBackToUnavailableReason() {
        let notification = JSONRPCMessageEnvelope.notification(
            method: "item/started",
            params: .object([
                "item": .object([
                    "id": .string("item_worker_2"),
                    "type": .string("toolCall"),
                    "worker": .object([
                        "id": .string("worker-2"),
                        "role": .string("reviewer"),
                    ]),
                ]),
            ])
        )

        let events = AppServerEventDecoder.decodeAll(notification)
        guard case let .action(action)? = events.first else {
            XCTFail("Expected action event")
            return
        }

        XCTAssertEqual(action.workerTrace?.workerID, "worker-2")
        XCTAssertEqual(action.workerTrace?.role, "reviewer")
        XCTAssertNil(action.workerTrace?.prompt)
        XCTAssertNil(action.workerTrace?.output)
        XCTAssertEqual(action.workerTrace?.unavailableReason, "trace unavailable from runtime")
    }

    func testExecutableCandidatesIncludeCommonFallbackPaths() {
        let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let candidates = CodexRuntime.executableCandidates(
            pathEnv: "/usr/bin:/bin",
            homeDirectory: homeDirectory
        )

        XCTAssertTrue(candidates.contains("/opt/homebrew/bin/codex"))
        XCTAssertTrue(candidates.contains("/usr/local/bin/codex"))
        XCTAssertTrue(candidates.contains("/Users/tester/.local/bin/codex"))
        XCTAssertTrue(candidates.contains("/Users/tester/bin/codex"))
    }

    func testMakeThreadStartParamsUsesCurrentApprovalPolicyAndSandboxFields() {
        let safety = RuntimeSafetyConfiguration(
            sandboxMode: .workspaceWrite,
            approvalPolicy: .onRequest,
            networkAccess: true,
            webSearch: .cached,
            writableRoots: ["/tmp/workspace"]
        )
        let params = CodexRuntime.makeThreadStartParams(
            cwd: "/tmp/workspace",
            safetyConfiguration: safety,
            includeWebSearch: true
        )

        XCTAssertEqual(params.value(at: ["approvalPolicy"])?.stringValue, "on-request")
        XCTAssertEqual(params.value(at: ["sandbox"])?.stringValue, "workspace-write")
        XCTAssertNil(params.value(at: ["sandboxPolicy"]))
    }

    func testMakeTurnStartParamsIncludesModelEffortAndExperimentalOptions() {
        let params = CodexRuntime.makeTurnStartParams(
            threadID: "thr_1",
            text: "hello",
            safetyConfiguration: nil,
            skillInputs: [],
            turnOptions: RuntimeTurnOptions(
                model: "gpt-5-codex",
                effort: "high",
                experimental: ["parallelToolCalls": true]
            ),
            includeWebSearch: true
        )

        XCTAssertEqual(params.value(at: ["model"])?.stringValue, "gpt-5-codex")
        XCTAssertEqual(params.value(at: ["effort"])?.stringValue, "high")
        XCTAssertEqual(params.value(at: ["experimental", "parallelToolCalls"])?.boolValue, true)
    }

    func testMakeTurnStartParamsIncludesAdditionalInputItems() {
        let params = CodexRuntime.makeTurnStartParams(
            threadID: "thr_1",
            text: "hello",
            safetyConfiguration: nil,
            skillInputs: [],
            inputItems: [
                .localImage(path: "/tmp/example.png"),
                .mention(name: "README.md", path: "/tmp/README.md"),
                .image(url: "https://example.com/example.png"),
            ],
            turnOptions: nil,
            includeWebSearch: true
        )

        let inputArray = params.value(at: ["input"])?.arrayValue ?? []
        XCTAssertEqual(inputArray.count, 4)

        XCTAssertEqual(inputArray[1].value(at: ["type"])?.stringValue, "localImage")
        XCTAssertEqual(inputArray[1].value(at: ["path"])?.stringValue, "/tmp/example.png")

        XCTAssertEqual(inputArray[2].value(at: ["type"])?.stringValue, "mention")
        XCTAssertEqual(inputArray[2].value(at: ["name"])?.stringValue, "README.md")
        XCTAssertEqual(inputArray[2].value(at: ["path"])?.stringValue, "/tmp/README.md")

        XCTAssertEqual(inputArray[3].value(at: ["type"])?.stringValue, "image")
        XCTAssertEqual(inputArray[3].value(at: ["url"])?.stringValue, "https://example.com/example.png")
    }

    func testMakeTurnStartParamsUsesLegacyReasoningEffortWhenRequested() {
        let params = CodexRuntime.makeTurnStartParams(
            threadID: "thr_1",
            text: "hello",
            safetyConfiguration: nil,
            skillInputs: [],
            turnOptions: RuntimeTurnOptions(
                model: "gpt-5-codex",
                effort: "medium",
                experimental: [:]
            ),
            includeWebSearch: true,
            useLegacyReasoningEffortField: true
        )

        XCTAssertEqual(params.value(at: ["reasoningEffort"])?.stringValue, "medium")
        XCTAssertNil(params.value(at: ["effort"]))
    }

    func testMakeTurnStartParamsOmitsEmptyTurnOptions() {
        let params = CodexRuntime.makeTurnStartParams(
            threadID: "thr_1",
            text: "hello",
            safetyConfiguration: nil,
            skillInputs: [],
            turnOptions: RuntimeTurnOptions(model: "   ", effort: "", experimental: [:]),
            includeWebSearch: true
        )

        XCTAssertNil(params.value(at: ["model"]))
        XCTAssertNil(params.value(at: ["effort"]))
        XCTAssertNil(params.value(at: ["experimental"]))
    }

    func testMakeTurnSteerParamsUsesExpectedTurnIdAndInputArray() {
        let params = CodexRuntime.makeTurnSteerParams(
            threadID: "thr_1",
            text: "Continue with tests",
            expectedTurnID: "turn_1"
        )

        XCTAssertEqual(params.value(at: ["threadId"])?.stringValue, "thr_1")
        XCTAssertEqual(params.value(at: ["expectedTurnId"])?.stringValue, "turn_1")
        let firstInput = params.value(at: ["input"])?.arrayValue?.first
        XCTAssertEqual(firstInput?.value(at: ["type"])?.stringValue, "text")
        XCTAssertEqual(firstInput?.value(at: ["text"])?.stringValue, "Continue with tests")
    }
}
