import Foundation

enum AppServerEventDecoder {
    static func decodeAll(_ notification: JSONRPCMessageEnvelope) -> [CodexRuntimeEvent] {
        guard notification.isNotification,
              let method = notification.method
        else {
            return []
        }

        let params = notification.params ?? .object([:])
        let threadID = stringValue(
            in: params,
            keyPaths: [["threadId"], ["thread_id"], ["thread", "id"], ["thread", "threadId"], ["thread", "thread_id"]]
        )
        let turnID = stringValue(
            in: params,
            keyPaths: [["turnId"], ["turn_id"], ["turn", "id"], ["turn", "turnId"], ["turn", "turn_id"]]
        )

        switch method {
        case "thread/started":
            guard let threadID = stringValue(
                in: params,
                keyPaths: [["thread", "id"], ["threadId"], ["thread_id"], ["thread", "threadId"], ["thread", "thread_id"]]
            ) else {
                return []
            }
            return [.threadStarted(threadID: threadID)]

        case "turn/started":
            guard let turnID = stringValue(
                in: params,
                keyPaths: [["turn", "id"], ["turnId"], ["turn_id"], ["turn", "turnId"], ["turn", "turn_id"]]
            ) else {
                return []
            }
            return [.turnStarted(threadID: threadID, turnID: turnID)]

        case "item/agentMessage/delta":
            guard let delta = params.value(at: ["delta"])?.stringValue,
                  !delta.isEmpty
            else {
                return []
            }

            let itemID = stringValue(in: params, keyPaths: [["itemId"], ["item_id"], ["item", "id"], ["item", "itemId"], ["item", "item_id"]])
                ?? "agent-message"
            let channel = parseAssistantMessageChannel(params: params)
            let stage = stringValue(
                in: params,
                keyPaths: [
                    ["stage"],
                    ["phase"],
                    ["progress", "stage"],
                    ["progress", "phase"],
                    ["item", "stage"],
                    ["item", "phase"],
                ]
            )

            let assistantDelta = RuntimeAssistantMessageDelta(
                itemID: itemID,
                threadID: threadID,
                turnID: turnID,
                delta: delta,
                channel: channel,
                stage: stage
            )

            return [.assistantMessageDelta(assistantDelta)]

        case "item/commandExecution/outputDelta":
            guard let itemID = stringValue(
                in: params,
                keyPaths: [["itemId"], ["item_id"], ["item", "id"], ["item", "itemId"], ["item", "item_id"]]
            ),
                let delta = params.value(at: ["delta"])?.stringValue,
                !delta.isEmpty
            else {
                return []
            }
            let output = RuntimeCommandOutputDelta(
                itemID: itemID,
                threadID: threadID,
                turnID: turnID,
                delta: delta
            )
            return [.commandOutputDelta(output)]

        case "item/fileChange/outputDelta":
            guard let itemID = stringValue(
                in: params,
                keyPaths: [["itemId"], ["item_id"], ["item", "id"], ["item", "itemId"], ["item", "item_id"]]
            ),
                let delta = params.value(at: ["delta"])?.stringValue,
                !delta.isEmpty
            else {
                return []
            }
            return [
                .fileChangeOutputDelta(
                    RuntimeFileChangeOutputDelta(
                        itemID: itemID,
                        threadID: threadID,
                        turnID: turnID,
                        delta: delta
                    )
                ),
            ]

        case "turn/followUpsSuggested":
            let suggestionValues: [JSONValue] = params.value(at: ["suggestions"])?.arrayValue ?? []
            let suggestions: [RuntimeFollowUpSuggestion] = suggestionValues.compactMap { value in
                guard let rawText = value.value(at: ["text"])?.stringValue else {
                    return nil
                }
                let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard
                    !text.isEmpty
                else { return nil }
                return RuntimeFollowUpSuggestion(
                    id: value.value(at: ["id"])?.stringValue,
                    text: text,
                    priority: value.value(at: ["priority"])?.intValue
                )
            }
            guard !suggestions.isEmpty else {
                return []
            }
            return [
                .followUpSuggestions(
                    RuntimeFollowUpSuggestionBatch(
                        threadID: threadID,
                        turnID: turnID,
                        suggestions: suggestions
                    )
                ),
            ]

        case "item/started", "item/completed":
            guard let item = params.value(at: ["item"]),
                  let itemType = item.value(at: ["type"])?.stringValue
            else {
                return []
            }

            let verb = method.hasSuffix("started") ? "Started" : "Completed"
            let workerTrace = parseWorkerTrace(params: params, item: item)
            let action = RuntimeAction(
                method: method,
                itemID: item.value(at: ["id"])?.stringValue,
                itemType: itemType,
                threadID: threadID,
                turnID: turnID,
                title: "\(verb) \(itemType)",
                detail: item.prettyPrinted(),
                workerTrace: workerTrace
            )

            var events: [CodexRuntimeEvent] = [.action(action)]
            if itemType == "fileChange" {
                let update = RuntimeFileChangeUpdate(
                    itemID: item.value(at: ["id"])?.stringValue,
                    threadID: threadID,
                    turnID: turnID,
                    status: item.value(at: ["status"])?.stringValue,
                    changes: parseFileChanges(from: item)
                )
                events.append(.fileChangesUpdated(update))
            }
            return events

        case "turn/completed":
            let completion = RuntimeTurnCompletion(
                threadID: threadID,
                turnID: stringValue(
                    in: params,
                    keyPaths: [["turn", "id"], ["turnId"], ["turn_id"], ["turn", "turnId"], ["turn", "turn_id"]]
                ),
                status: params.value(at: ["turn", "status"])?.stringValue ?? "unknown",
                errorMessage: params.value(at: ["turn", "error", "message"])?.stringValue
            )
            return [.turnCompleted(completion)]

        case "serverRequest/resolved":
            return [
                .serverRequestResolved(
                    RuntimeServerRequestResolution(
                        requestID: intValue(
                            in: params,
                            keyPaths: [["requestId"], ["request_id"], ["serverRequestId"], ["server_request_id"]]
                        ),
                        method: stringValue(in: params, keyPaths: [["method"], ["requestMethod"], ["request_method"]]),
                        threadID: threadID,
                        turnID: turnID,
                        itemID: stringValue(
                            in: params,
                            keyPaths: [["itemId"], ["item_id"], ["item", "id"], ["item", "itemId"], ["item", "item_id"]]
                        ),
                        detail: params.prettyPrinted()
                    )
                ),
            ]

        case "thread/status/changed":
            guard let status = stringValue(in: params, keyPaths: [["status"], ["thread", "status"]]) else {
                return []
            }
            return [.threadStatusUpdated(RuntimeThreadStatusUpdate(threadID: threadID, status: status))]

        case "thread/tokenUsage/updated":
            return [
                .tokenUsageUpdated(
                    RuntimeTokenUsageUpdate(
                        threadID: threadID,
                        inputTokens: intValue(
                            in: params,
                            keyPaths: [["usage", "inputTokens"], ["usage", "input_tokens"], ["inputTokens"], ["input_tokens"]]
                        ),
                        outputTokens: intValue(
                            in: params,
                            keyPaths: [["usage", "outputTokens"], ["usage", "output_tokens"], ["outputTokens"], ["output_tokens"]]
                        ),
                        totalTokens: intValue(
                            in: params,
                            keyPaths: [["usage", "totalTokens"], ["usage", "total_tokens"], ["totalTokens"], ["total_tokens"]]
                        )
                    )
                ),
            ]

        case "turn/diff/updated":
            return [
                .turnDiffUpdated(
                    RuntimeTurnDiffUpdate(
                        threadID: threadID,
                        turnID: turnID,
                        diff: stringValue(in: params, keyPaths: [["diff"], ["patch"]]),
                        rawPayload: params
                    )
                ),
            ]

        case "turn/plan/updated":
            return [
                .turnPlanUpdated(
                    RuntimeTurnPlanUpdate(
                        threadID: threadID,
                        turnID: turnID,
                        summary: stringValue(in: params, keyPaths: [["summary"], ["plan", "summary"], ["text"]]),
                        rawPayload: params
                    )
                ),
            ]

        case "model/rerouted":
            return [
                .modelRerouted(
                    RuntimeModelReroute(
                        threadID: threadID,
                        turnID: turnID,
                        fromModel: stringValue(in: params, keyPaths: [["fromModel"], ["from_model"], ["from"]]),
                        toModel: stringValue(in: params, keyPaths: [["toModel"], ["to_model"], ["to"]]),
                        reason: stringValue(in: params, keyPaths: [["reason"], ["message"]])
                    )
                ),
            ]

        case "error":
            guard let message = stringValue(in: params, keyPaths: [["message"], ["error", "message"]]) else {
                return []
            }
            return [
                .runtimeError(
                    RuntimeErrorNotice(
                        threadID: threadID,
                        turnID: turnID,
                        itemID: stringValue(
                            in: params,
                            keyPaths: [["itemId"], ["item_id"], ["item", "id"], ["item", "itemId"], ["item", "item_id"]]
                        ),
                        code: stringValue(in: params, keyPaths: [["code"], ["error", "code"]]),
                        message: message,
                        rawPayload: params
                    )
                ),
            ]

        case "account/updated":
            let mode = RuntimeAuthMode(rawMode: params.value(at: ["authMode"])?.stringValue)
            return [.accountUpdated(authMode: mode)]

        case "account/login/completed":
            let completion = RuntimeLoginCompleted(
                loginID: params.value(at: ["loginId"])?.stringValue,
                success: params.value(at: ["success"])?.boolValue ?? false,
                error: params.value(at: ["error"])?.stringValue
            )
            return [.accountLoginCompleted(completion)]

        default:
            return [.unknownNotification(RuntimeUnknownNotification(method: method, params: params))]
        }
    }

    private static func parseFileChanges(from item: JSONValue) -> [RuntimeFileChange] {
        let values = item.value(at: ["changes"])?.arrayValue ?? []
        return values.compactMap { value in
            guard let path = value.value(at: ["path"])?.stringValue else {
                return nil
            }
            let kind = value.value(at: ["kind"])?.stringValue ?? "update"
            let diff = value.value(at: ["diff"])?.stringValue
            return RuntimeFileChange(path: path, kind: kind, diff: diff)
        }
    }

    private static func parseWorkerTrace(params: JSONValue, item: JSONValue) -> RuntimeAction.WorkerTrace? {
        let worker = item.value(at: ["worker"])
            ?? item.value(at: ["subagent"])
            ?? params.value(at: ["worker"])
            ?? params.value(at: ["subagent"])

        let workerID = worker?.value(at: ["id"])?.stringValue
            ?? item.value(at: ["workerId"])?.stringValue
            ?? item.value(at: ["subagentId"])?.stringValue
            ?? params.value(at: ["workerId"])?.stringValue
            ?? params.value(at: ["subagentId"])?.stringValue

        let role = worker?.value(at: ["role"])?.stringValue
            ?? worker?.value(at: ["name"])?.stringValue
            ?? item.value(at: ["workerRole"])?.stringValue
            ?? item.value(at: ["subagentRole"])?.stringValue

        let prompt = worker?.value(at: ["prompt"])?.stringValue
            ?? worker?.value(at: ["promptText"])?.stringValue
            ?? item.value(at: ["prompt"])?.stringValue
            ?? item.value(at: ["workerPrompt"])?.stringValue
            ?? item.value(at: ["subagentPrompt"])?.stringValue

        let output = worker?.value(at: ["output"])?.stringValue
            ?? worker?.value(at: ["result"])?.stringValue
            ?? item.value(at: ["output"])?.stringValue
            ?? item.value(at: ["workerOutput"])?.stringValue
            ?? item.value(at: ["subagentOutput"])?.stringValue

        let status = worker?.value(at: ["status"])?.stringValue
            ?? item.value(at: ["workerStatus"])?.stringValue
            ?? item.value(at: ["subagentStatus"])?.stringValue

        var unavailableReason = worker?.value(at: ["traceUnavailableReason"])?.stringValue
            ?? item.value(at: ["traceUnavailableReason"])?.stringValue
            ?? item.value(at: ["workerTraceUnavailableReason"])?.stringValue
            ?? item.value(at: ["subagentTraceUnavailableReason"])?.stringValue

        let hasWorkerContext = worker != nil
            || workerID != nil
            || role != nil
            || item.value(at: ["worker"]) != nil
            || item.value(at: ["subagent"]) != nil

        if hasWorkerContext,
           prompt == nil,
           output == nil,
           unavailableReason == nil
        {
            unavailableReason = "trace unavailable from runtime"
        }

        let trace = RuntimeAction.WorkerTrace(
            workerID: workerID,
            role: role,
            prompt: prompt,
            output: output,
            status: status,
            unavailableReason: unavailableReason
        )

        let hasAnyValue = trace.workerID != nil
            || trace.role != nil
            || trace.prompt != nil
            || trace.output != nil
            || trace.status != nil
            || trace.unavailableReason != nil
        return hasAnyValue ? trace : nil
    }

    private static func parseAssistantMessageChannel(params: JSONValue) -> RuntimeAssistantMessageChannel {
        let raw = stringValue(
            in: params,
            keyPaths: [
                ["channel"],
                ["messageChannel"],
                ["message_channel"],
                ["item", "channel"],
                ["item", "messageChannel"],
                ["item", "message_channel"],
            ]
        )

        if let raw {
            return RuntimeAssistantMessageChannel(rawChannel: raw)
        }

        // Some runtimes may communicate assistant stream kind through item.type.
        let itemType = stringValue(
            in: params,
            keyPaths: [
                ["item", "type"],
                ["itemType"],
                ["item_type"],
            ]
        )

        guard let itemType else {
            return .finalResponse
        }

        let normalized = itemType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("progress")
            || normalized.contains("intermediate")
            || normalized.contains("intermediary")
            || normalized.contains("thinking")
            || normalized.contains("status")
        {
            return .progress
        }

        if normalized.contains("system") || normalized.contains("meta") {
            return .system
        }

        return .finalResponse
    }

    private static func stringValue(in payload: JSONValue, keyPaths: [[String]]) -> String? {
        for keyPath in keyPaths {
            guard let raw = payload.value(at: keyPath)?.stringValue else {
                continue
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func intValue(in payload: JSONValue, keyPaths: [[String]]) -> Int? {
        for keyPath in keyPaths {
            if let value = payload.value(at: keyPath)?.intValue {
                return value
            }
            if let raw = payload.value(at: keyPath)?.stringValue,
               let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                return value
            }
        }
        return nil
    }
}
