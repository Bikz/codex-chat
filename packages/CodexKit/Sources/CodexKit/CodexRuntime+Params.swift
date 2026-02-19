import Foundation

extension CodexRuntime {
    static func makeThreadStartParams(
        cwd: String?,
        safetyConfiguration: RuntimeSafetyConfiguration?,
        includeWebSearch: Bool,
        useLegacySandboxPolicy: Bool = false
    ) -> JSONValue {
        var params: [String: JSONValue] = [:]
        if let cwd {
            params["cwd"] = .string(cwd)
        }

        if let safetyConfiguration {
            params["approvalPolicy"] = .string(safetyConfiguration.approvalPolicy.rawValue)
            if useLegacySandboxPolicy {
                params["sandboxPolicy"] = makeSandboxPolicy(
                    cwd: cwd,
                    safetyConfiguration: safetyConfiguration
                )
            } else {
                params["sandbox"] = .string(makeThreadSandboxMode(safetyConfiguration.sandboxMode))
            }
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
        turnOptions: RuntimeTurnOptions?,
        includeWebSearch: Bool,
        useLegacyReasoningEffortField: Bool = false
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

        if let turnOptions {
            if let model = turnOptions.model?.trimmingCharacters(in: .whitespacesAndNewlines),
               !model.isEmpty
            {
                params["model"] = .string(model)
            }

            if let effort = turnOptions.effort?.trimmingCharacters(in: .whitespacesAndNewlines),
               !effort.isEmpty
            {
                params[useLegacyReasoningEffortField ? "reasoningEffort" : "effort"] = .string(effort)
            }

            if !turnOptions.experimental.isEmpty {
                let experimental = Dictionary(uniqueKeysWithValues: turnOptions.experimental.map { key, value in
                    (key, JSONValue.bool(value))
                })
                params["experimental"] = .object(experimental)
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

    static func makeTurnSteerParams(
        threadID: String,
        text: String,
        expectedTurnID: String
    ) -> JSONValue {
        .object([
            "threadId": .string(threadID),
            "expectedTurnId": .string(expectedTurnID),
            "input": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(text),
                ]),
            ]),
        ])
    }

    static func makeLegacyTurnSteerParams(
        threadID: String,
        text: String,
        turnID: String
    ) -> JSONValue {
        .object([
            "threadId": .string(threadID),
            "turnId": .string(turnID),
            "text": .string(text),
        ])
    }

    static func shouldRetryWithoutWebSearch(error: CodexRuntimeError) -> Bool {
        guard case let .rpcError(_, message) = error else {
            return false
        }
        let lowered = message.lowercased()
        let indicatesSchemaIssue = lowered.contains("unknown")
            || lowered.contains("invalid")
            || lowered.contains("unsupported")
        return (lowered.contains("websearch") || lowered.contains("web_search"))
            && indicatesSchemaIssue
    }

    static func shouldRetryWithoutSkillInput(error: CodexRuntimeError) -> Bool {
        guard case let .rpcError(_, message) = error else {
            return false
        }
        let lowered = message.lowercased()
        let indicatesSchemaIssue = lowered.contains("unknown")
            || lowered.contains("invalid")
            || lowered.contains("unsupported")
        return lowered.contains("skill")
            && indicatesSchemaIssue
    }

    static func shouldRetryWithLegacyThreadStartSandboxField(error: CodexRuntimeError) -> Bool {
        guard case let .rpcError(_, message) = error else {
            return false
        }
        let lowered = message.lowercased()
        let mentionsSandboxField = lowered.contains("sandbox")
        let indicatesSchemaMismatch = lowered.contains("unknown field")
            || lowered.contains("missing field")
            || lowered.contains("invalid type")
        return mentionsSandboxField && indicatesSchemaMismatch
    }

    static func shouldRetryWithLegacyReasoningEffortField(error: CodexRuntimeError) -> Bool {
        guard case let .rpcError(_, message) = error else {
            return false
        }
        let lowered = message.lowercased()
        guard lowered.contains("effort"), !lowered.contains("unsupported value") else {
            return false
        }
        return lowered.contains("unknown field")
            || lowered.contains("missing field")
            || lowered.contains("invalid type")
    }

    static func shouldRetryWithLegacyTurnSteerPayload(error: CodexRuntimeError) -> Bool {
        guard case let .rpcError(code, message) = error else {
            return false
        }
        if code == -32601 {
            return false
        }

        let lowered = message.lowercased()
        let indicatesSchemaMismatch = lowered.contains("invalid request")
            || lowered.contains("unknown field")
            || lowered.contains("missing field")
            || lowered.contains("invalid type")
        guard indicatesSchemaMismatch else {
            return false
        }

        let mentionsPayloadFields = lowered.contains("expectedturnid")
            || lowered.contains("turnid")
            || lowered.contains("input")
            || lowered.contains("text")
        let mentionsActiveTurnIssue = lowered.contains("no active turn")
            || lowered.contains("does not match")
            || lowered.contains("did not match")
        return mentionsPayloadFields && !mentionsActiveTurnIssue
    }

    static func makeThreadSandboxMode(_ sandboxMode: RuntimeSandboxMode) -> String {
        switch sandboxMode {
        case .readOnly:
            "read-only"
        case .workspaceWrite:
            "workspace-write"
        case .dangerFullAccess:
            "danger-full-access"
        }
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
