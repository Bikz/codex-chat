import Foundation

struct AdaptiveConcurrencyRefreshState: Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var latestReason: String?
    private(set) var isTaskRunning: Bool = false

    mutating func schedule(reason: String) -> UInt64? {
        generation = generation &+ 1
        latestReason = reason
        guard !isTaskRunning else {
            return nil
        }
        isTaskRunning = true
        return generation
    }

    func refreshReasonIfReady(for generation: UInt64) -> String? {
        guard self.generation == generation else {
            return nil
        }
        return latestReason
    }

    mutating func markIdle() {
        isTaskRunning = false
    }
}
