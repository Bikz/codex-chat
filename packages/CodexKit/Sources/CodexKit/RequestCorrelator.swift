import Foundation

actor RequestCorrelator {
    private var nextID: Int
    private var pending: [RequestKey: CheckedContinuation<JSONRPCMessageEnvelope, Error>] = [:]
    private var bufferedResponses: [RequestKey: JSONRPCMessageEnvelope] = [:]
    private var bufferedFailures: [RequestKey: Error] = [:]
    private var terminalError: Error?

    init(startingID: Int = 1) {
        nextID = startingID
    }

    func makeRequestID() -> JSONRPCID {
        defer { nextID += 1 }
        return .string(String(nextID))
    }

    func resetTransport() {
        terminalError = nil
        bufferedResponses.removeAll(keepingCapacity: false)
        bufferedFailures.removeAll(keepingCapacity: false)
    }

    func suspendResponse(id: JSONRPCID) async throws -> JSONRPCMessageEnvelope {
        let key = requestKey(for: id)

        if let terminalError {
            throw terminalError
        }

        if let failure = bufferedFailures.removeValue(forKey: key) {
            throw failure
        }

        if let buffered = bufferedResponses.removeValue(forKey: key) {
            return buffered
        }

        return try await withCheckedThrowingContinuation { continuation in
            pending[key] = continuation
        }
    }

    @discardableResult
    func resolveResponse(_ response: JSONRPCMessageEnvelope) -> Bool {
        guard let id = response.id,
              terminalError == nil
        else { return false }
        let key = requestKey(for: id)

        if let continuation = pending.removeValue(forKey: key) {
            continuation.resume(returning: response)
            return true
        }

        bufferedResponses[key] = response
        return true
    }

    @discardableResult
    func failResponse(id: JSONRPCID, error: Error) -> Bool {
        guard terminalError == nil else { return false }
        let key = requestKey(for: id)

        if let continuation = pending.removeValue(forKey: key) {
            continuation.resume(throwing: error)
            return true
        }

        bufferedFailures[key] = error
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

    private func requestKey(for id: JSONRPCID) -> RequestKey {
        switch id {
        case let .int(value):
            return .numeric(String(value))
        case let .string(value):
            if let numeric = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return .numeric(String(numeric))
            }
            return .text(value)
        }
    }
}

private enum RequestKey: Hashable {
    case numeric(String)
    case text(String)
}
