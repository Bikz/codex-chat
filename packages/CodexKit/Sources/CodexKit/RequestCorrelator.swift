import Foundation

actor RequestCorrelator {
    private var nextID: Int
    private var pending: [Int: CheckedContinuation<JSONRPCMessageEnvelope, Error>] = [:]
    private var bufferedResponses: [Int: JSONRPCMessageEnvelope] = [:]
    private var bufferedFailures: [Int: Error] = [:]
    private var terminalError: Error?

    init(startingID: Int = 1) {
        nextID = startingID
    }

    func makeRequestID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    func resetTransport() {
        terminalError = nil
        bufferedResponses.removeAll(keepingCapacity: false)
        bufferedFailures.removeAll(keepingCapacity: false)
    }

    func suspendResponse(id: Int) async throws -> JSONRPCMessageEnvelope {
        if let terminalError {
            throw terminalError
        }

        if let failure = bufferedFailures.removeValue(forKey: id) {
            throw failure
        }

        if let buffered = bufferedResponses.removeValue(forKey: id) {
            return buffered
        }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
        }
    }

    @discardableResult
    func resolveResponse(_ response: JSONRPCMessageEnvelope) -> Bool {
        guard let id = response.id,
              terminalError == nil
        else { return false }

        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(returning: response)
            return true
        }

        bufferedResponses[id] = response
        return true
    }

    @discardableResult
    func failResponse(id: Int, error: Error) -> Bool {
        guard terminalError == nil else { return false }

        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(throwing: error)
            return true
        }

        bufferedFailures[id] = error
        return true
    }

    func failAll(error: Error) {
        terminalError = error
        let continuations = pending.values
        pending.removeAll(keepingCapacity: false)
        bufferedResponses.removeAll(keepingCapacity: false)
        bufferedFailures.removeAll(keepingCapacity: false)
        continuations.forEach { $0.resume(throwing: error) }
    }
}
