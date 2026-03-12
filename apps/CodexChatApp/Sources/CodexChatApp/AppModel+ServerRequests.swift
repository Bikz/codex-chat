import CodexKit
import Foundation

extension AppModel {
    enum ServerRequestSubmissionError: LocalizedError {
        case requestNotFound(Int)
        case runtimeUnavailable

        var errorDescription: String? {
            switch self {
            case let .requestNotFound(requestID):
                "Server request \(requestID) was not found."
            case .runtimeUnavailable:
                "Codex runtime is unavailable."
            }
        }
    }

    func submitPermissionsRequestResponse(
        requestID: Int,
        permissions: Set<String>,
        scope: String?
    ) {
        submitServerRequestResponse(
            requestID: requestID,
            response: .permissions(
                permissions: permissions.sorted(),
                scope: normalizedServerRequestResponseText(scope)
            )
        )
    }

    func declinePermissionsRequest(requestID: Int) {
        submitServerRequestResponse(
            requestID: requestID,
            response: .permissions(permissions: [], scope: nil)
        )
    }

    func submitUserInputRequestResponse(
        requestID: Int,
        text: String?,
        optionID: String?
    ) {
        submitServerRequestResponse(
            requestID: requestID,
            response: .userInput(
                text: normalizedServerRequestResponseText(text),
                optionID: normalizedServerRequestResponseText(optionID)
            )
        )
    }

    func submitMCPElicitationResponse(requestID: Int, text: String?) {
        submitServerRequestResponse(
            requestID: requestID,
            response: .mcpElicitation(text: normalizedServerRequestResponseText(text))
        )
    }

    func submitDynamicToolCallResponse(requestID: Int, approved: Bool) {
        submitServerRequestResponse(
            requestID: requestID,
            response: .dynamicToolCall(approved: approved)
        )
    }

    func submitRemotePermissionsRequestResponse(
        requestID: Int,
        permissions: Set<String>,
        scope: String?
    ) async throws {
        try await submitRemoteServerRequestResponse(
            requestID: requestID,
            response: .permissions(
                permissions: permissions.sorted(),
                scope: normalizedServerRequestResponseText(scope)
            )
        )
    }

    func submitRemoteUserInputRequestResponse(
        requestID: Int,
        text: String?,
        optionID: String?
    ) async throws {
        try await submitRemoteServerRequestResponse(
            requestID: requestID,
            response: .userInput(
                text: normalizedServerRequestResponseText(text),
                optionID: normalizedServerRequestResponseText(optionID)
            )
        )
    }

    func submitRemoteMCPElicitationResponse(requestID: Int, text: String?) async throws {
        try await submitRemoteServerRequestResponse(
            requestID: requestID,
            response: .mcpElicitation(text: normalizedServerRequestResponseText(text))
        )
    }

    func submitRemoteDynamicToolCallResponse(requestID: Int, approved: Bool) async throws {
        try await submitRemoteServerRequestResponse(
            requestID: requestID,
            response: .dynamicToolCall(approved: approved)
        )
    }

    func resolvePendingServerRequest(id requestID: Int) -> RuntimeServerRequest? {
        if let activeServerRequest, activeServerRequest.id == requestID {
            return activeServerRequest
        }

        if let request = unscopedServerRequests.first(where: { $0.id == requestID }) {
            return request
        }

        guard let threadID = serverRequestStateMachine.threadID(for: requestID) else {
            return nil
        }
        return serverRequestStateMachine.pendingByThreadID[threadID]?.first(where: { $0.id == requestID })
    }

    func resolveRuntimeServerRequest(
        id requestID: Int,
        statusMessage: String? = nil,
        autoDrainReason: String = "server request resolved"
    ) {
        serverRequestResolutionFallbackTasksByRequestID[requestID]?.cancel()
        serverRequestResolutionFallbackTasksByRequestID.removeValue(forKey: requestID)
        serverRequestDecisionInFlightRequestIDs.remove(requestID)

        _ = serverRequestStateMachine.resolve(id: requestID)
        unscopedServerRequests.removeAll(where: { $0.id == requestID })
        syncApprovalPresentationState()

        if let statusMessage {
            serverRequestStatusMessage = statusMessage
        }
        requestAutoDrain(reason: autoDrainReason)
    }

    private func submitServerRequestResponse(
        requestID: Int,
        response: RuntimeServerRequestResponse
    ) {
        guard let request = resolvePendingServerRequest(id: requestID) else {
            return
        }
        guard let runtimePool else {
            return
        }

        serverRequestDecisionInFlightRequestIDs.insert(request.id)
        serverRequestStatusMessage = nil

        Task {
            do {
                try await performServerRequestResponse(
                    response,
                    request: request,
                    runtimePool: runtimePool
                )
            } catch {
                serverRequestStatusMessage = "Failed to answer runtime request: \(error.localizedDescription)"
                recordRuntimeRequestSupportEvent(
                    phase: .failed,
                    summary: runtimeRequestSupportSummary(for: request)
                )
                appendLog(.error, "Server request response failed: \(error.localizedDescription)")
            }
        }
    }

    private func submitRemoteServerRequestResponse(
        requestID: Int,
        response: RuntimeServerRequestResponse
    ) async throws {
        guard let request = resolvePendingServerRequest(id: requestID) else {
            throw ServerRequestSubmissionError.requestNotFound(requestID)
        }
        guard let runtimePool else {
            throw ServerRequestSubmissionError.runtimeUnavailable
        }

        try await performServerRequestResponse(response, request: request, runtimePool: runtimePool)
    }

    private func performServerRequestResponse(
        _ response: RuntimeServerRequestResponse,
        request: RuntimeServerRequest,
        runtimePool: RuntimePool
    ) async throws {
        serverRequestDecisionInFlightRequestIDs.insert(request.id)
        serverRequestStatusMessage = nil

        defer {
            serverRequestDecisionInFlightRequestIDs.remove(request.id)
        }

        try await runtimePool.respondToServerRequest(requestID: request.id, response: response)
        let statusMessage = serverRequestResponseStatusMessage(for: request, response: response)
        serverRequestStatusMessage = statusMessage
        recordRuntimeRequestSupportEvent(
            phase: .responded,
            summary: runtimeRequestSupportSummary(for: request)
        )
        appendLog(.info, statusMessage)
        scheduleServerRequestResolutionFallback(
            requestID: request.id,
            statusMessage: statusMessage
        )
    }

    private func scheduleServerRequestResolutionFallback(requestID: Int, statusMessage: String?) {
        serverRequestResolutionFallbackTasksByRequestID[requestID]?.cancel()
        serverRequestResolutionFallbackTasksByRequestID[requestID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self,
                  resolvePendingServerRequest(id: requestID) != nil
            else {
                return
            }

            resolveRuntimeServerRequest(
                id: requestID,
                statusMessage: statusMessage,
                autoDrainReason: "server request fallback resolved"
            )
            appendLog(
                .warning,
                "Server request \(requestID) resolved locally after runtime did not emit serverRequest/resolved in time."
            )
        }
    }

    private func normalizedServerRequestResponseText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private func serverRequestResponseStatusMessage(
        for request: RuntimeServerRequest,
        response: RuntimeServerRequestResponse
    ) -> String {
        switch (request, response) {
        case let (.permissions(permissionRequest), .permissions(permissions, scope)):
            if permissions.isEmpty {
                return "Declined permission request \(permissionRequest.id)."
            }
            if let scope, !scope.isEmpty {
                return "Granted \(permissions.count) permission(s) for request \(permissionRequest.id) with scope \(scope)."
            }
            return "Granted \(permissions.count) permission(s) for request \(permissionRequest.id)."
        case let (.userInput(userInputRequest), .userInput(text, optionID)):
            if let optionID {
                return "Answered input request \(userInputRequest.id) with option \(optionID)."
            }
            if let text, !text.isEmpty {
                return "Answered input request \(userInputRequest.id)."
            }
            return "Dismissed input request \(userInputRequest.id)."
        case let (.mcpElicitation(mcpRequest), .mcpElicitation(text)):
            if let text, !text.isEmpty {
                return "Answered MCP elicitation \(mcpRequest.id)."
            }
            return "Dismissed MCP elicitation \(mcpRequest.id)."
        case let (.dynamicToolCall(toolRequest), .dynamicToolCall(approved)):
            return approved
                ? "Approved dynamic tool call \(toolRequest.id)."
                : "Declined dynamic tool call \(toolRequest.id)."
        case let (.approval(approvalRequest), .approval(decision)):
            return "Answered approval request \(approvalRequest.id) with \(serverRequestApprovalDecisionLabel(decision))."
        default:
            return "Answered runtime request \(request.id)."
        }
    }

    private func serverRequestApprovalDecisionLabel(_ decision: RuntimeApprovalDecision) -> String {
        switch decision {
        case .approveOnce:
            "Approve once"
        case .approveForSession:
            "Approve for session"
        case .decline:
            "Decline"
        case .cancel:
            "Cancel"
        }
    }
}
