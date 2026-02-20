import CodexKit
import Foundation

struct ApprovalStateMachine {
    private(set) var pendingByThreadID: [UUID: [RuntimeApprovalRequest]] = [:]
    private(set) var requestToThreadID: [Int: UUID] = [:]

    var hasPendingApprovals: Bool {
        !requestToThreadID.isEmpty
    }

    var pendingThreadIDs: Set<UUID> {
        Set(pendingByThreadID.keys)
    }

    var firstPendingRequest: RuntimeApprovalRequest? {
        for requests in pendingByThreadID.values {
            if let first = requests.first {
                return first
            }
        }
        return nil
    }

    func pendingRequest(for threadID: UUID) -> RuntimeApprovalRequest? {
        pendingByThreadID[threadID]?.first
    }

    func pendingRequestCount(for threadID: UUID) -> Int {
        pendingByThreadID[threadID]?.count ?? 0
    }

    func threadID(for requestID: Int) -> UUID? {
        requestToThreadID[requestID]
    }

    mutating func enqueue(_ request: RuntimeApprovalRequest, threadID: UUID) {
        if requestToThreadID[request.id] != nil {
            return
        }

        pendingByThreadID[threadID, default: []].append(request)
        requestToThreadID[request.id] = threadID
    }

    @discardableResult
    mutating func resolve(id: Int) -> UUID? {
        guard let threadID = requestToThreadID.removeValue(forKey: id) else {
            return nil
        }

        guard var requests = pendingByThreadID[threadID] else {
            return threadID
        }

        requests.removeAll(where: { $0.id == id })
        if requests.isEmpty {
            pendingByThreadID.removeValue(forKey: threadID)
        } else {
            pendingByThreadID[threadID] = requests
        }

        return threadID
    }

    mutating func clear() {
        pendingByThreadID.removeAll()
        requestToThreadID.removeAll()
    }
}
