import CodexKit
import Foundation

enum RuntimeTurnOptionsCompatibilityPolicy {
    static func shouldRetryWithoutTurnOptions(for error: Error) -> Bool {
        let detail: String
        if let runtimeError = error as? CodexRuntimeError {
            switch runtimeError {
            case let .rpcError(_, message):
                detail = message
            case let .invalidResponse(message):
                detail = message
            default:
                return false
            }
        } else {
            detail = error.localizedDescription
        }

        let lowered = detail.lowercased()
        let indicatesUnsupported = lowered.contains("unknown")
            || lowered.contains("invalid")
            || lowered.contains("unsupported value")
            || lowered.contains("unsupported")
        let referencesTurnOptions = lowered.contains("model")
            || lowered.contains("reasoning")
            || lowered.contains("reasoningeffort")
            || lowered.contains("reasoning_effort")
            || lowered.contains("reasoning.effort")
            || lowered.contains("effort")
        return indicatesUnsupported && referencesTurnOptions
    }
}
