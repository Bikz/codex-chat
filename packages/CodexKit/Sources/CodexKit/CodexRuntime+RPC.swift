import Foundation

extension CodexRuntime {
    public func respondToApproval(
        requestID: Int,
        decision: RuntimeApprovalDecision
    ) throws {
        guard pendingApprovalRequests.removeValue(forKey: requestID) != nil else {
            throw CodexRuntimeError.invalidResponse("Unknown approval request id: \(requestID)")
        }
        try writeMessage(JSONRPCMessageEnvelope.response(id: requestID, result: decision.rpcResult))
    }

    func handleIncomingMessage(_ message: JSONRPCMessageEnvelope) async throws {
        if message.isResponse {
            _ = await correlator.resolveResponse(message)
            return
        }

        if message.isServerRequest {
            try await handleServerRequest(message)
            return
        }

        for event in AppServerEventDecoder.decodeAll(message) {
            eventContinuation.yield(event)
        }
    }

    private func handleServerRequest(_ request: JSONRPCMessageEnvelope) async throws {
        guard let id = request.id,
              let method = request.method
        else {
            return
        }

        if method.hasSuffix("/requestApproval") {
            let approval = Self.decodeApprovalRequest(
                requestID: id,
                method: method,
                params: request.params
            )
            pendingApprovalRequests[id] = approval
            eventContinuation.yield(.approvalRequested(approval))
            return
        }

        let error = JSONRPCResponseErrorEnvelope(
            code: -32601,
            message: "Unsupported client method: \(method)",
            data: nil
        )
        try writeMessage(JSONRPCMessageEnvelope.response(id: id, error: error))
    }

    func performHandshake() async throws {
        let params: JSONValue = .object([
            "clientInfo": .object([
                "name": .string("codexchat_app"),
                "title": .string("CodexChat"),
                "version": .string("0.1.0"),
            ]),
        ])

        let result = try await sendRequest(method: "initialize", params: params, timeoutSeconds: 10)
        runtimeCapabilities = Self.decodeCapabilities(from: result)
        try sendNotification(method: "initialized", params: .object([:]))
    }

    func sendRequest(
        method: String,
        params: JSONValue,
        timeoutSeconds: TimeInterval = 20
    ) async throws -> JSONValue {
        guard process != nil else {
            throw CodexRuntimeError.processNotRunning
        }

        let requestID = await correlator.makeRequestID()
        let request = JSONRPCRequestEnvelope(id: requestID, method: method, params: params)
        try writeMessage(request)

        let timeoutTask = Task { [correlator] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            _ = await correlator.failResponse(
                id: requestID,
                error: CodexRuntimeError.timedOut("waiting for \(method)")
            )
        }

        defer { timeoutTask.cancel() }

        let response = try await correlator.suspendResponse(id: requestID)

        if let rpcError = response.error {
            throw CodexRuntimeError.rpcError(code: rpcError.code, message: rpcError.message)
        }

        guard let result = response.result else {
            throw CodexRuntimeError.invalidResponse("Missing result payload for \(method)")
        }

        return result
    }

    private func sendNotification(method: String, params: JSONValue) throws {
        let notification = JSONRPCRequestEnvelope(id: nil, method: method, params: params)
        try writeMessage(notification)
    }

    private func writeMessage(_ payload: some Encodable) throws {
        guard let stdinHandle else {
            throw CodexRuntimeError.processNotRunning
        }

        var data = try encoder.encode(payload)
        data.append(0x0A)
        stdinHandle.write(data)
    }

    private static func decodeCapabilities(from initializeResult: JSONValue) -> RuntimeCapabilities {
        let capabilities = initializeResult.value(at: ["capabilities"])
        let supportsTurnSteer = capabilities?.value(at: ["turnSteer"])?.boolValue ?? false

        let followUpCapability = capabilities?.value(at: ["followUpSuggestions"])
        let supportsFollowUpSuggestions = if let boolValue = followUpCapability?.boolValue {
            boolValue
        } else if followUpCapability?.objectValue != nil {
            true
        } else {
            false
        }

        return RuntimeCapabilities(
            supportsTurnSteer: supportsTurnSteer,
            supportsFollowUpSuggestions: supportsFollowUpSuggestions
        )
    }

    static func decodeModelList(from result: JSONValue) throws -> RuntimeModelList {
        guard let data = result.value(at: ["data"])?.arrayValue else {
            throw CodexRuntimeError.invalidResponse("model/list missing result.data[]")
        }

        let models = try data.map { value in
            guard let object = value.objectValue else {
                throw CodexRuntimeError.invalidResponse("model/list item is not an object")
            }

            let rawID = object["id"]?.stringValue ?? object["model"]?.stringValue ?? ""
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                throw CodexRuntimeError.invalidResponse("model/list item missing id/model")
            }

            let rawModel = object["model"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = (rawModel?.isEmpty == false) ? rawModel! : id

            let rawDisplayName = object["displayName"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (rawDisplayName?.isEmpty == false) ? rawDisplayName! : model

            let rawDescription = object["description"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = (rawDescription?.isEmpty == false) ? rawDescription : nil

            let rawDefaultEffort = object["defaultReasoningEffort"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultReasoningEffort = (rawDefaultEffort?.isEmpty == false) ? rawDefaultEffort : nil

            let supportedWebSearchModes = decodeSupportedWebSearchModes(from: object)
            let rawDefaultWebSearchMode = (
                object["defaultWebSearchMode"]?.stringValue
                    ?? object["defaultWebSearch"]?.stringValue
                    ?? object["default_web_search_mode"]?.stringValue
                    ?? object["default_web_search"]?.stringValue
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultWebSearchMode = parseRuntimeWebSearchMode(rawDefaultWebSearchMode)

            let rawUpgrade = object["upgrade"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let upgrade = (rawUpgrade?.isEmpty == false) ? rawUpgrade : nil

            let supportedReasoningValues = object["supportedReasoningEfforts"]?.arrayValue ?? []
            let supportedReasoningEfforts: [RuntimeReasoningEffortOption] = supportedReasoningValues.compactMap { entry in
                let rawReasoningEffort = entry.value(at: ["reasoningEffort"])?.stringValue ?? ""
                let reasoningEffort = rawReasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !reasoningEffort.isEmpty else {
                    return nil
                }

                let rawEntryDescription = (entry.value(at: ["description"])?.stringValue ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let entryDescription = rawEntryDescription.isEmpty ? nil : rawEntryDescription
                return RuntimeReasoningEffortOption(
                    reasoningEffort: reasoningEffort,
                    description: entryDescription
                )
            }

            return RuntimeModelInfo(
                id: id,
                model: model,
                displayName: displayName,
                description: description,
                supportedReasoningEfforts: supportedReasoningEfforts,
                defaultReasoningEffort: defaultReasoningEffort,
                supportedWebSearchModes: supportedWebSearchModes,
                defaultWebSearchMode: defaultWebSearchMode,
                isDefault: object["isDefault"]?.boolValue ?? false,
                upgrade: upgrade
            )
        }

        let rawNextCursor = result.value(at: ["nextCursor"])?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextCursor = (rawNextCursor?.isEmpty == false) ? rawNextCursor : nil
        return RuntimeModelList(models: models, nextCursor: nextCursor)
    }

    private static func decodeSupportedWebSearchModes(from object: [String: JSONValue]) -> [RuntimeWebSearchMode]? {
        let explicitModeKeys = [
            "supportedWebSearchModes",
            "supported_web_search_modes",
            "webSearchModes",
            "web_search_modes",
        ]

        for key in explicitModeKeys {
            guard let entries = object[key]?.arrayValue else {
                continue
            }

            var seen: Set<RuntimeWebSearchMode> = []
            return entries.compactMap { entry -> RuntimeWebSearchMode? in
                let rawValue = (
                    entry.stringValue
                        ?? entry.value(at: ["mode"])?.stringValue
                        ?? entry.value(at: ["webSearch"])?.stringValue
                        ?? entry.value(at: ["web_search"])?.stringValue
                )?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let mode = parseRuntimeWebSearchMode(rawValue),
                      seen.insert(mode).inserted
                else {
                    return nil
                }
                return mode
            }
        }

        let supportsWebSearch = object["supportsWebSearch"]?.boolValue
            ?? object["supports_web_search"]?.boolValue
        if let supportsWebSearch {
            return supportsWebSearch ? RuntimeWebSearchMode.allCases : [.disabled]
        }

        return nil
    }

    private static func parseRuntimeWebSearchMode(_ rawValue: String?) -> RuntimeWebSearchMode? {
        let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalized {
        case RuntimeWebSearchMode.cached.rawValue:
            return .cached
        case RuntimeWebSearchMode.live.rawValue:
            return .live
        case RuntimeWebSearchMode.disabled.rawValue, "none", "off":
            return .disabled
        default:
            return nil
        }
    }
}
