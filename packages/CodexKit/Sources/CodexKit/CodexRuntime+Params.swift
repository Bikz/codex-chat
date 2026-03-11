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
        inputItems: [RuntimeInputItem] = [],
        turnOptions: RuntimeTurnOptions?,
        includeWebSearch: Bool,
        useLegacyReasoningEffortField: Bool = false
    ) -> JSONValue {
        var payloadInputItems: [JSONValue] = [
            .object([
                "type": .string("text"),
                "text": .string(text),
            ]),
        ]
        if !skillInputs.isEmpty {
            payloadInputItems.append(
                contentsOf: skillInputs.map { input in
                    .object([
                        "type": .string("skill"),
                        "name": .string(input.name),
                        "path": .string(input.path),
                    ])
                }
            )
        }
        if !inputItems.isEmpty {
            payloadInputItems.append(
                contentsOf: inputItems.map(encodeRuntimeInputItem)
            )
        }

        var params: [String: JSONValue] = [
            "threadId": .string(threadID),
            "input": .array(payloadInputItems),
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

    static func encodeRuntimeInputItem(_ item: RuntimeInputItem) -> JSONValue {
        switch item {
        case let .text(text):
            .object([
                "type": .string("text"),
                "text": .string(text),
            ])
        case let .image(url):
            .object([
                "type": .string("image"),
                "url": .string(url),
            ])
        case let .localImage(path):
            .object([
                "type": .string("localImage"),
                "path": .string(path),
            ])
        case let .skill(input):
            .object([
                "type": .string("skill"),
                "name": .string(input.name),
                "path": .string(input.path),
            ])
        case let .mention(name, path):
            .object([
                "type": .string("mention"),
                "name": .string(name),
                "path": .string(path),
            ])
        }
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

    static func shouldRetryWithoutInputItems(error: CodexRuntimeError) -> Bool {
        guard case let .rpcError(_, message) = error else {
            return false
        }
        let lowered = message.lowercased()
        let indicatesSchemaIssue = lowered.contains("unknown")
            || lowered.contains("invalid")
            || lowered.contains("unsupported")
        let mentionsAttachmentOrMention = lowered.contains("localimage")
            || lowered.contains("mention")
            || (lowered.contains("image") && lowered.contains("url"))
        return mentionsAttachmentOrMention
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

    static func decodeServerRequest(
        requestID: Int,
        method: String,
        params: JSONValue?
    ) -> RuntimeServerRequest? {
        if method.hasSuffix("/requestApproval") {
            return .approval(
                decodeApprovalRequest(
                    requestID: requestID,
                    method: method,
                    params: params
                )
            )
        }

        if method == "item/permissions/requestApproval" {
            return .permissions(
                decodePermissionsRequest(
                    requestID: requestID,
                    method: method,
                    params: params
                )
            )
        }

        if method == "item/tool/requestUserInput" {
            return .userInput(
                decodeUserInputRequest(
                    requestID: requestID,
                    method: method,
                    params: params
                )
            )
        }

        if method == "mcpServer/elicitation/request" {
            return .mcpElicitation(
                decodeMCPElicitationRequest(
                    requestID: requestID,
                    method: method,
                    params: params
                )
            )
        }

        if method == "item/tool/call" {
            return .dynamicToolCall(
                decodeDynamicToolCallRequest(
                    requestID: requestID,
                    method: method,
                    params: params
                )
            )
        }

        return nil
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

        let commandValue = firstValue(
            in: payload,
            keyPaths: [
                ["command"],
                ["parsedCmd"],
                ["parsed_cmd"],
                ["command", "argv"],
                ["command", "command"],
            ]
        )
        let command: [String] = if let array = commandValue?.arrayValue {
            array.compactMap(\.stringValue)
        } else if let single = commandValue?.stringValue {
            [single]
        } else {
            []
        }

        let rawChanges = firstValue(
            in: payload,
            keyPaths: [
                ["changes"],
                ["fileChanges"],
                ["file_changes"],
                ["fileChange", "changes"],
                ["file_change", "changes"],
                ["item", "changes"],
            ]
        )?.arrayValue ?? []
        let changes: [RuntimeFileChange] = rawChanges.compactMap { change in
            guard let path = change.value(at: ["path"])?.stringValue else {
                return nil
            }
            let kind = change.value(at: ["kind"])?.stringValue
                ?? change.value(at: ["changeKind"])?.stringValue
                ?? change.value(at: ["change_kind"])?.stringValue
                ?? "update"
            let diff = change.value(at: ["diff"])?.stringValue
                ?? change.value(at: ["patch"])?.stringValue
            return RuntimeFileChange(path: path, kind: kind, diff: diff)
        }

        let availableDecisions = decodeAvailableApprovalDecisions(from: payload)

        return RuntimeApprovalRequest(
            id: requestID,
            kind: kind,
            method: method,
            threadID: firstString(
                in: payload,
                keyPaths: [
                    ["threadId"],
                    ["thread_id"],
                    ["thread", "id"],
                    ["thread", "threadId"],
                    ["thread", "thread_id"],
                ]
            ),
            turnID: firstString(
                in: payload,
                keyPaths: [
                    ["turnId"],
                    ["turn_id"],
                    ["turn", "id"],
                    ["turn", "turnId"],
                    ["turn", "turn_id"],
                ]
            ),
            itemID: firstString(
                in: payload,
                keyPaths: [
                    ["itemId"],
                    ["item_id"],
                    ["item", "id"],
                    ["item", "itemId"],
                    ["item", "item_id"],
                ]
            ),
            reason: firstString(in: payload, keyPaths: [["reason"], ["message"]]),
            risk: firstString(in: payload, keyPaths: [["risk"], ["safetyRisk"], ["safety_risk"]]),
            cwd: firstString(in: payload, keyPaths: [["cwd"], ["workingDirectory"], ["working_directory"]]),
            command: command,
            changes: changes,
            availableDecisions: availableDecisions.isEmpty ? [.approveOnce, .approveForSession, .decline] : availableDecisions,
            grantRoot: firstString(in: payload, keyPaths: [["grantRoot"], ["grant_root"]]),
            networkContext: firstString(in: payload, keyPaths: [["networkApprovalContext"], ["network_approval_context"]]),
            detail: payload.prettyPrinted(),
            rawPayload: payload
        )
    }

    static func decodePermissionsRequest(
        requestID: Int,
        method: String,
        params: JSONValue?
    ) -> RuntimePermissionsRequest {
        let payload = params ?? .object([:])
        let additionalPermissions = firstValue(
            in: payload,
            keyPaths: [["additionalPermissions"], ["additional_permissions"], ["permissions"]]
        )?.arrayValue ?? []
        let permissions = additionalPermissions.compactMap { value in
            value.stringValue ?? value.value(at: ["name"])?.stringValue ?? value.value(at: ["permission"])?.stringValue
        }

        return RuntimePermissionsRequest(
            id: requestID,
            method: method,
            threadID: threadID(from: payload),
            turnID: turnID(from: payload),
            itemID: itemID(from: payload),
            reason: firstString(in: payload, keyPaths: [["reason"], ["message"]]),
            cwd: firstString(in: payload, keyPaths: [["cwd"], ["workingDirectory"], ["working_directory"]]),
            permissions: permissions,
            grantRoot: firstString(in: payload, keyPaths: [["grantRoot"], ["grant_root"]]),
            detail: payload.prettyPrinted(),
            rawPayload: payload
        )
    }

    static func decodeUserInputRequest(
        requestID: Int,
        method: String,
        params: JSONValue?
    ) -> RuntimeUserInputRequest {
        let payload = params ?? .object([:])
        let options = firstValue(in: payload, keyPaths: [["options"]])?.arrayValue ?? []
        let decodedOptions = options.enumerated().compactMap { index, option -> RuntimeUserInputOption? in
            let label = option.value(at: ["label"])?.stringValue
                ?? option.value(at: ["text"])?.stringValue
                ?? option.stringValue
            guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let optionID = option.value(at: ["id"])?.stringValue ?? "option_\(index)"
            return RuntimeUserInputOption(
                id: optionID,
                label: label,
                description: option.value(at: ["description"])?.stringValue
            )
        }

        return RuntimeUserInputRequest(
            id: requestID,
            method: method,
            threadID: threadID(from: payload),
            turnID: turnID(from: payload),
            itemID: itemID(from: payload),
            title: firstString(in: payload, keyPaths: [["title"], ["header"]]),
            prompt: firstString(in: payload, keyPaths: [["prompt"], ["message"], ["question"]]) ?? "Runtime requested input.",
            placeholder: firstString(in: payload, keyPaths: [["placeholder"]]),
            value: firstString(in: payload, keyPaths: [["value"], ["defaultValue"], ["default_value"]]),
            options: decodedOptions,
            detail: payload.prettyPrinted(),
            rawPayload: payload
        )
    }

    static func decodeMCPElicitationRequest(
        requestID: Int,
        method: String,
        params: JSONValue?
    ) -> RuntimeMCPElicitationRequest {
        let payload = params ?? .object([:])
        return RuntimeMCPElicitationRequest(
            id: requestID,
            method: method,
            threadID: threadID(from: payload),
            turnID: turnID(from: payload),
            itemID: itemID(from: payload),
            serverName: firstString(in: payload, keyPaths: [["serverName"], ["server_name"], ["server", "name"]]),
            prompt: firstString(in: payload, keyPaths: [["prompt"], ["message"], ["question"]]) ?? "MCP server requested input.",
            detail: payload.prettyPrinted(),
            rawPayload: payload
        )
    }

    static func decodeDynamicToolCallRequest(
        requestID: Int,
        method: String,
        params: JSONValue?
    ) -> RuntimeDynamicToolCallRequest {
        let payload = params ?? .object([:])
        return RuntimeDynamicToolCallRequest(
            id: requestID,
            method: method,
            threadID: threadID(from: payload),
            turnID: turnID(from: payload),
            itemID: itemID(from: payload),
            toolName: firstString(in: payload, keyPaths: [["toolName"], ["tool_name"], ["tool", "name"]]) ?? "dynamic_tool_call",
            arguments: firstValue(in: payload, keyPaths: [["arguments"], ["args"], ["toolArguments"], ["tool_arguments"]]),
            detail: payload.prettyPrinted(),
            rawPayload: payload
        )
    }

    private static func decodeAvailableApprovalDecisions(from payload: JSONValue) -> [RuntimeApprovalOption] {
        let rawValues = firstValue(
            in: payload,
            keyPaths: [["availableDecisions"], ["available_decisions"]]
        )?.arrayValue ?? []

        var seen: Set<RuntimeApprovalOption> = []
        return rawValues.compactMap { value in
            guard let raw = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let option = RuntimeApprovalOption(rawValue: raw),
                  seen.insert(option).inserted
            else {
                return nil
            }
            return option
        }
    }

    private static func threadID(from payload: JSONValue) -> String? {
        firstString(
            in: payload,
            keyPaths: [
                ["threadId"],
                ["thread_id"],
                ["thread", "id"],
                ["thread", "threadId"],
                ["thread", "thread_id"],
            ]
        )
    }

    private static func turnID(from payload: JSONValue) -> String? {
        firstString(
            in: payload,
            keyPaths: [
                ["turnId"],
                ["turn_id"],
                ["turn", "id"],
                ["turn", "turnId"],
                ["turn", "turn_id"],
            ]
        )
    }

    private static func itemID(from payload: JSONValue) -> String? {
        firstString(
            in: payload,
            keyPaths: [
                ["itemId"],
                ["item_id"],
                ["item", "id"],
                ["item", "itemId"],
                ["item", "item_id"],
            ]
        )
    }

    private static func firstValue(in payload: JSONValue, keyPaths: [[String]]) -> JSONValue? {
        for keyPath in keyPaths {
            if let value = payload.value(at: keyPath),
               value != .null
            {
                return value
            }
        }
        return nil
    }

    private static func firstString(in payload: JSONValue, keyPaths: [[String]]) -> String? {
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
}
