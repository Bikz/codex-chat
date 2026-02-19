import Foundation

enum AppServerEventDecoder {
    static func decodeAll(_ notification: JSONRPCMessageEnvelope) -> [CodexRuntimeEvent] {
        guard notification.isNotification,
              let method = notification.method
        else {
            return []
        }

        let params = notification.params ?? .object([:])
        let threadID = params.value(at: ["threadId"])?.stringValue
            ?? params.value(at: ["thread", "id"])?.stringValue
        let turnID = params.value(at: ["turnId"])?.stringValue
            ?? params.value(at: ["turn", "id"])?.stringValue

        switch method {
        case "thread/started":
            guard let threadID = params.value(at: ["thread", "id"])?.stringValue else {
                return []
            }
            return [.threadStarted(threadID: threadID)]

        case "turn/started":
            guard let turnID = params.value(at: ["turn", "id"])?.stringValue else {
                return []
            }
            return [.turnStarted(turnID: turnID)]

        case "item/agentMessage/delta":
            guard let delta = params.value(at: ["delta"])?.stringValue,
                  !delta.isEmpty
            else {
                return []
            }

            let itemID = params.value(at: ["itemId"])?.stringValue
                ?? params.value(at: ["item", "id"])?.stringValue
                ?? "agent-message"

            return [.assistantMessageDelta(itemID: itemID, delta: delta)]

        case "item/commandExecution/outputDelta":
            guard let itemID = params.value(at: ["itemId"])?.stringValue
                ?? params.value(at: ["item", "id"])?.stringValue,
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
                turnID: params.value(at: ["turn", "id"])?.stringValue,
                status: params.value(at: ["turn", "status"])?.stringValue ?? "unknown",
                errorMessage: params.value(at: ["turn", "error", "message"])?.stringValue
            )
            return [.turnCompleted(completion)]

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
            return []
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
}
