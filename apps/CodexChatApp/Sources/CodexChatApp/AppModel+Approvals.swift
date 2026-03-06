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

        Task {
            do {
                try await performApprovalDecision(decision, request: request, runtimePool: runtimePool)
            } catch {
                approvalStatusMessage = "Failed to send approval decision: \(error.localizedDescription)"
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
        _ = approvalStateMachine.resolve(id: request.id)
        unscopedApprovalRequests.removeAll(where: { $0.id == request.id })
        syncApprovalPresentationState()
        approvalStatusMessage = "Sent decision: \(approvalDecisionLabel(decision))."
        appendLog(.info, "Approval decision sent for request \(request.id): \(approvalDecisionLabel(decision))")
        requestAutoDrain(reason: "approval resolved")
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
}
