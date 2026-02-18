import CodexKit
import Foundation

struct ApprovalStateMachine {
    private(set) var activeRequest: RuntimeApprovalRequest?
    private(set) var queuedRequests: [RuntimeApprovalRequest] = []

    var hasPendingApprovals: Bool {
        activeRequest != nil || !queuedRequests.isEmpty
    }

    mutating func enqueue(_ request: RuntimeApprovalRequest) {
        if activeRequest?.id == request.id || queuedRequests.contains(where: { $0.id == request.id }) {
            return
        }

        guard activeRequest != nil else {
            activeRequest = request
            return
        }

        queuedRequests.append(request)
    }

    mutating func resolve(id: Int) -> RuntimeApprovalRequest? {
        if activeRequest?.id == id {
            activeRequest = queuedRequests.isEmpty ? nil : queuedRequests.removeFirst()
            return activeRequest
        }

        queuedRequests.removeAll(where: { $0.id == id })
        return activeRequest
    }

    mutating func clear() {
        activeRequest = nil
        queuedRequests.removeAll()
    }
}
