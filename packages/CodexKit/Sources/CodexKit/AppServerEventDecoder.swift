import Foundation

enum AppServerEventDecoder {
    static func decode(_ notification: JSONRPCMessageEnvelope) -> CodexRuntimeEvent? {
        guard notification.isNotification,
              let method = notification.method else {
            return nil
        }

        let params = notification.params ?? .object([:])

        switch method {
        case "thread/started":
            guard let threadID = params.value(at: ["thread", "id"])?.stringValue else {
                return nil
            }
            return .threadStarted(threadID: threadID)

        case "turn/started":
            guard let turnID = params.value(at: ["turn", "id"])?.stringValue else {
                return nil
            }
            return .turnStarted(turnID: turnID)

        case "item/agentMessage/delta":
            guard let delta = params.value(at: ["delta"])?.stringValue,
                  !delta.isEmpty else {
                return nil
            }

            let itemID = params.value(at: ["itemId"])?.stringValue
                ?? params.value(at: ["item", "id"])?.stringValue
                ?? "agent-message"

            return .assistantMessageDelta(itemID: itemID, delta: delta)

        case "item/started", "item/completed":
            guard let item = params.value(at: ["item"]),
                  let itemType = item.value(at: ["type"])?.stringValue else {
                return nil
            }

            let verb = method.hasSuffix("started") ? "Started" : "Completed"
            let action = RuntimeAction(
                method: method,
                itemID: item.value(at: ["id"])?.stringValue,
                itemType: itemType,
                title: "\(verb) \(itemType)",
                detail: item.prettyPrinted()
            )
            return .action(action)

        case "turn/completed":
            let completion = RuntimeTurnCompletion(
                turnID: params.value(at: ["turn", "id"])?.stringValue,
                status: params.value(at: ["turn", "status"])?.stringValue ?? "unknown",
                errorMessage: params.value(at: ["turn", "error", "message"])?.stringValue
            )
            return .turnCompleted(completion)

        case "account/updated":
            let mode = RuntimeAuthMode(rawMode: params.value(at: ["authMode"])?.stringValue)
            return .accountUpdated(authMode: mode)

        case "account/login/completed":
            let completion = RuntimeLoginCompleted(
                loginID: params.value(at: ["loginId"])?.stringValue,
                success: params.value(at: ["success"])?.boolValue ?? false,
                error: params.value(at: ["error"])?.stringValue
            )
            return .accountLoginCompleted(completion)

        default:
            return nil
        }
    }
}
