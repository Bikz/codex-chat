import Foundation

actor RequestCorrelator {
    private var nextID: Int
    private var pending: [Int: CheckedContinuation<JSONRPCMessageEnvelope, Error>] = [:]

    init(startingID: Int = 1) {
        nextID = startingID
    }

    func makeRequestID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    func suspendResponse(id: Int) async throws -> JSONRPCMessageEnvelope {
        try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
        }
    }

    @discardableResult
    func resolveResponse(_ response: JSONRPCMessageEnvelope) -> Bool {
        guard let id = response.id,
              let continuation = pending.removeValue(forKey: id)
        else {
            return false
        }

        continuation.resume(returning: response)
        return true
    }

    @discardableResult
    func failResponse(id: Int, error: Error) -> Bool {
        guard let continuation = pending.removeValue(forKey: id) else {
            return false
        }

        continuation.resume(throwing: error)
        return true
    }

    func failAll(error: Error) {
        let continuations = pending.values
        pending.removeAll(keepingCapacity: false)
        continuations.forEach { $0.resume(throwing: error) }
    }
}
