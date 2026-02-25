import CodexKit
import Foundation

extension AppModel {
    func approvePendingApprovalOnce() {
        submitApprovalDecision(.approveOnce)
    }

    func approvePendingApprovalForSession() {
        submitApprovalDecision(.approveForSession)
    }

    func declinePendingApproval() {
        submitApprovalDecision(.decline)
    }

    func submitRemoteApprovalDecision(_ decision: RuntimeApprovalDecision, requestID: Int?) {
        submitApprovalDecision(decision, requestID: requestID)
    }

    private func submitApprovalDecision(_ decision: RuntimeApprovalDecision, requestID: Int? = nil) {
        let resolvedRequest: RuntimeApprovalRequest? = if let requestID {
            resolvePendingApprovalRequest(id: requestID)
        } else {
            pendingApprovalForSelectedThread
                ?? unscopedApprovalRequests.first
                ?? approvalStateMachine.firstPendingRequest
        }
        guard let request = resolvedRequest, let runtimePool else { return }

        approvalDecisionInFlightRequestIDs.insert(request.id)
        isApprovalDecisionInProgress = true
        approvalStatusMessage = nil

        Task {
            defer {
                approvalDecisionInFlightRequestIDs.remove(request.id)
                isApprovalDecisionInProgress = !approvalDecisionInFlightRequestIDs.isEmpty
            }

            do {
                try await runtimePool.respondToApproval(requestID: request.id, decision: decision)
                _ = approvalStateMachine.resolve(id: request.id)
                unscopedApprovalRequests.removeAll(where: { $0.id == request.id })
                syncApprovalPresentationState()
                approvalStatusMessage = "Sent decision: \(approvalDecisionLabel(decision))."
                appendLog(.info, "Approval decision sent for request \(request.id): \(approvalDecisionLabel(decision))")
                requestAutoDrain(reason: "approval resolved")
            } catch {
                approvalStatusMessage = "Failed to send approval decision: \(error.localizedDescription)"
                appendLog(.error, "Approval decision failed: \(error.localizedDescription)")
            }
        }
    }

    private func resolvePendingApprovalRequest(id requestID: Int) -> RuntimeApprovalRequest? {
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
