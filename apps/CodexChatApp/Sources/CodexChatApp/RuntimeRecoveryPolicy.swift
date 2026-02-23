import Foundation

enum RuntimeRecoveryPolicy {
    static let defaultAppAutoRecoveryBackoffSeconds: [UInt64] = [1, 2, 4, 8]
    static let maxAppAutoRecoveryAttempts = 8
    static let defaultMaxConsecutiveWorkerRecoveryFailures = 4

    static func appAutoRecoveryBackoffSeconds(
        environmentValue rawValue: String?,
        fallback: [UInt64] = defaultAppAutoRecoveryBackoffSeconds,
        maxAttempts: Int = maxAppAutoRecoveryAttempts
    ) -> [UInt64] {
        guard let rawValue,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return fallback
        }

        let parsed = rawValue
            .split(separator: ",")
            .compactMap { chunk -> UInt64? in
                let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                return UInt64(trimmed)
            }
        guard !parsed.isEmpty else {
            return fallback
        }
        return Array(parsed.prefix(max(1, maxAttempts)))
    }

    static func workerRestartBackoffSeconds(forConsecutiveFailureCount failureCount: Int) -> UInt64 {
        let normalizedFailureCount = max(1, failureCount)
        let backoffExponent = min(3, normalizedFailureCount - 1)
        return UInt64(1 << backoffExponent)
    }

    static func shouldAttemptWorkerRestart(
        forConsecutiveFailureCount failureCount: Int,
        maxConsecutiveFailures: Int = defaultMaxConsecutiveWorkerRecoveryFailures
    ) -> Bool {
        max(1, failureCount) <= max(1, maxConsecutiveFailures)
    }

    static func nextConsecutiveWorkerFailureCount(
        previousCount: Int,
        didRecover: Bool
    ) -> Int {
        didRecover ? 0 : max(0, previousCount) + 1
    }
}
