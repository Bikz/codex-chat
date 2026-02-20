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

    private func submitApprovalDecision(_ decision: RuntimeApprovalDecision) {
        guard let request = pendingApprovalForSelectedThread
            ?? unscopedApprovalRequest
            ?? approvalStateMachine.firstPendingRequest,
            let runtimePool
        else {
            return
        }

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
                if unscopedApprovalRequest?.id == request.id {
                    unscopedApprovalRequest = nil
                }
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
