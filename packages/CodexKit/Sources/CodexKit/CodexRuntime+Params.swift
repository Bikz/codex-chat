import Foundation

extension CodexRuntime {
    static func makeThreadStartParams(
        cwd: String?,
        safetyConfiguration: RuntimeSafetyConfiguration?,
        includeWebSearch: Bool
    ) -> JSONValue {
        var params: [String: JSONValue] = [:]
        if let cwd {
            params["cwd"] = .string(cwd)
        }

        if let safetyConfiguration {
            params["approvalPolicy"] = .string(safetyConfiguration.approvalPolicy.rawValue)
            params["sandboxPolicy"] = makeSandboxPolicy(
                cwd: cwd,
                safetyConfiguration: safetyConfiguration
            )
            if includeWebSearch {
                params["webSearch"] = .string(safetyConfiguration.webSearch.rawValue)
            }
        }

        return .object(params)
    }

    static func makeTurnStartParams(
        threadID: String,
        text: String,
        safetyConfiguration: RuntimeSafetyConfiguration?,
        skillInputs: [RuntimeSkillInput],
        includeWebSearch: Bool
    ) -> JSONValue {
        var inputItems: [JSONValue] = [
            .object([
                "type": .string("text"),
                "text": .string(text),
            ]),
        ]
        if !skillInputs.isEmpty {
            inputItems.append(
                contentsOf: skillInputs.map { input in
                    .object([
                        "type": .string("skill"),
                        "name": .string(input.name),
                        "path": .string(input.path),
                    ])
                }
            )
        }

        var params: [String: JSONValue] = [
            "threadId": .string(threadID),
            "input": .array(inputItems),
        ]

        if let safetyConfiguration {
            params["approvalPolicy"] = .string(safetyConfiguration.approvalPolicy.rawValue)
            params["sandboxPolicy"] = makeSandboxPolicy(
                cwd: nil,
                safetyConfiguration: safetyConfiguration
            )
            if includeWebSearch {
                params["webSearch"] = .string(safetyConfiguration.webSearch.rawValue)
            }
        }

        return .object(params)
    }

    static func makeSandboxPolicy(
        cwd: String?,
        safetyConfiguration: RuntimeSafetyConfiguration
    ) -> JSONValue {
        switch safetyConfiguration.sandboxMode {
        case .readOnly:
            return .object(["type": .string(RuntimeSandboxMode.readOnly.rawValue)])
        case .workspaceWrite:
            var roots = safetyConfiguration.writableRoots
            if roots.isEmpty, let cwd {
                roots = [cwd]
            }
            return .object([
                "type": .string(RuntimeSandboxMode.workspaceWrite.rawValue),
                "writableRoots": .array(roots.map(JSONValue.string)),
                "networkAccess": .bool(safetyConfiguration.networkAccess),
            ])
        case .dangerFullAccess:
            return .object(["type": .string(RuntimeSandboxMode.dangerFullAccess.rawValue)])
        }
    }

    static func shouldRetryWithoutWebSearch(error: CodexRuntimeError) -> Bool {
        guard case let .rpcError(_, message) = error else {
            return false
        }
        let lowered = message.lowercased()
        return (lowered.contains("websearch") || lowered.contains("web_search"))
            && (lowered.contains("unknown") || lowered.contains("invalid"))
    }

    static func shouldRetryWithoutSkillInput(error: CodexRuntimeError) -> Bool {
        guard case let .rpcError(_, message) = error else {
            return false
        }
        let lowered = message.lowercased()
        return lowered.contains("skill")
            && (lowered.contains("unknown") || lowered.contains("invalid"))
    }

    static func decodeApprovalRequest(
        requestID: Int,
        method: String,
        params: JSONValue?
    ) -> RuntimeApprovalRequest {
        let payload = params ?? .object([:])
        let kind: RuntimeApprovalKind = if method.contains("commandExecution") {
            .commandExecution
        } else if method.contains("fileChange") {
            .fileChange
        } else {
            .unknown
        }

        let command: [String] = if let array = payload.value(at: ["command"])?.arrayValue {
            array.compactMap(\.stringValue)
        } else if let parsed = payload.value(at: ["parsedCmd"])?.arrayValue {
            parsed.compactMap(\.stringValue)
        } else if let single = payload.value(at: ["command"])?.stringValue {
            [single]
        } else {
            []
        }

        let changes: [RuntimeFileChange] = (payload.value(at: ["changes"])?.arrayValue ?? []).compactMap { change in
            guard let path = change.value(at: ["path"])?.stringValue else {
                return nil
            }
            let kind = change.value(at: ["kind"])?.stringValue ?? "update"
            let diff = change.value(at: ["diff"])?.stringValue
            return RuntimeFileChange(path: path, kind: kind, diff: diff)
        }

        return RuntimeApprovalRequest(
            id: requestID,
            kind: kind,
            method: method,
            threadID: payload.value(at: ["threadId"])?.stringValue,
            turnID: payload.value(at: ["turnId"])?.stringValue,
            itemID: payload.value(at: ["itemId"])?.stringValue,
            reason: payload.value(at: ["reason"])?.stringValue,
            risk: payload.value(at: ["risk"])?.stringValue,
            cwd: payload.value(at: ["cwd"])?.stringValue,
            command: command,
            changes: changes,
            detail: payload.prettyPrinted()
        )
    }
}
