import CodexKit
import Foundation

extension AppModel {
    enum ApprovalDecisionSubmissionError: LocalizedError {
        case requestNotFound(Int)
        case runtimeUnavailable

        var errorDescription: String? {
            switch self {
            case let .requestNotFound(requestID):
                "Approval request \(requestID) was not found."
            case .runtimeUnavailable:
                "Codex runtime is unavailable."
            }
        }
    }

    func approvePendingApprovalOnce() {
        submitApprovalDecision(.approveOnce)
    }

    func approvePendingApprovalForSession() {
        submitApprovalDecision(.approveForSession)
    }

    func declinePendingApproval() {
        submitApprovalDecision(.decline)
    }

    func submitRemoteApprovalDecision(
        _ decision: RuntimeApprovalDecision,
        requestID: Int
    ) async throws {
        guard let request = resolvePendingApprovalRequest(id: requestID) else {
            throw ApprovalDecisionSubmissionError.requestNotFound(requestID)
        }
        guard let runtimePool else {
            throw ApprovalDecisionSubmissionError.runtimeUnavailable
        }

        try await performApprovalDecision(decision, request: request, runtimePool: runtimePool)
    }

    private func submitApprovalDecision(_ decision: RuntimeApprovalDecision, requestID: Int? = nil) {
        let resolvedRequest: RuntimeApprovalRequest? = if let requestID {
            resolvePendingApprovalRequest(id: requestID)
        } else {
            pendingApprovalForSelectedThread
                ?? unscopedApprovalRequests.first
                ?? approvalStateMachine.firstPendingRequest
        }
        guard let request = resolvedRequest else { return }
        guard let runtimePool else { return }

        approvalDecisionInFlightRequestIDs.insert(request.id)
        isApprovalDecisionInProgress = true
        approvalStatusMessage = nil

        Task {
            do {
                try await performApprovalDecision(decision, request: request, runtimePool: runtimePool)
            } catch {
                approvalStatusMessage = "Failed to send approval decision: \(error.localizedDescription)"
                recordRuntimeRequestSupportEvent(
                    phase: .failed,
                    summary: runtimeRequestSupportSummary(for: request)
                )
                appendLog(.error, "Approval decision failed: \(error.localizedDescription)")
            }
        }
    }

    func resolvePendingApprovalRequest(id requestID: Int) -> RuntimeApprovalRequest? {
        if let activeApprovalRequest, activeApprovalRequest.id == requestID {
            return activeApprovalRequest
        }

        if let request = unscopedApprovalRequests.first(where: { $0.id == requestID }) {
            return request
        }

        guard let threadID = approvalStateMachine.threadID(for: requestID) else {
            return nil
        }
        return approvalStateMachine.pendingByThreadID[threadID]?.first(where: { $0.id == requestID })
    }

    func resolveRuntimeApprovalRequest(
        id requestID: Int,
        statusMessage: String? = nil,
        autoDrainReason: String = "approval resolved"
    ) {
        approvalResolutionFallbackTasksByRequestID[requestID]?.cancel()
        approvalResolutionFallbackTasksByRequestID.removeValue(forKey: requestID)
        approvalDecisionInFlightRequestIDs.remove(requestID)
        isApprovalDecisionInProgress = !approvalDecisionInFlightRequestIDs.isEmpty

        _ = approvalStateMachine.resolve(id: requestID)
        unscopedApprovalRequests.removeAll(where: { $0.id == requestID })
        syncApprovalPresentationState()

        if let statusMessage {
            approvalStatusMessage = statusMessage
        }
        requestAutoDrain(reason: autoDrainReason)
    }

    private func performApprovalDecision(
        _ decision: RuntimeApprovalDecision,
        request: RuntimeApprovalRequest,
        runtimePool: RuntimePool
    ) async throws {
        approvalDecisionInFlightRequestIDs.insert(request.id)
        isApprovalDecisionInProgress = true
        approvalStatusMessage = nil

        defer {
            approvalDecisionInFlightRequestIDs.remove(request.id)
            isApprovalDecisionInProgress = !approvalDecisionInFlightRequestIDs.isEmpty
        }

        try await runtimePool.respondToApproval(requestID: request.id, decision: decision)
        approvalStatusMessage = "Sent decision: \(approvalDecisionLabel(decision))."
        recordRuntimeRequestSupportEvent(
            phase: .responded,
            summary: runtimeRequestSupportSummary(for: request)
        )
        appendLog(.info, "Approval decision sent for request \(request.id): \(approvalDecisionLabel(decision))")
        scheduleApprovalResolutionFallback(
            requestID: request.id,
            statusMessage: approvalStatusMessage
        )
    }

    private func approvalDecisionLabel(_ decision: RuntimeApprovalDecision) -> String {
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

    private func scheduleApprovalResolutionFallback(requestID: Int, statusMessage: String?) {
        approvalResolutionFallbackTasksByRequestID[requestID]?.cancel()
        approvalResolutionFallbackTasksByRequestID[requestID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self,
                  resolvePendingApprovalRequest(id: requestID) != nil
            else {
                return
            }

            resolveRuntimeApprovalRequest(
                id: requestID,
                statusMessage: statusMessage,
                autoDrainReason: "approval fallback resolved"
            )
            appendLog(.warning, "Approval \(requestID) resolved locally after runtime did not emit serverRequest/resolved in time.")
        }
    }
}
