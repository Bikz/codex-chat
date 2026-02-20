import Foundation

actor AdaptiveConcurrencyController {
    struct Signals: Sendable {
        var queuedTurns: Int
        var activeTurns: Int
        var workerCount: Int
        var degradedWorkerCount: Int
        var totalWorkerFailures: Int
        var selectedThreadIsActive: Bool
        var memoryPressure: Bool
    }

    private let minimumLimit: Int
    private let hardMaximumLimit: Int
    private var currentLimit: Int
    private var previousFailureCount: Int = 0

    init(minimumLimit: Int = 2, hardMaximumLimit: Int) {
        self.minimumLimit = max(1, minimumLimit)
        self.hardMaximumLimit = max(self.minimumLimit, hardMaximumLimit)
        currentLimit = self.minimumLimit
    }

    func nextLimit(signals: Signals) -> Int {
        let workerCount = max(1, signals.workerCount)
        let baselineLimit = min(hardMaximumLimit, max(minimumLimit, workerCount * 8))
        var target = baselineLimit

        if signals.queuedTurns > 0 {
            target = min(hardMaximumLimit, baselineLimit + min(48, signals.queuedTurns))
        }

        let failureDelta = max(0, signals.totalWorkerFailures - previousFailureCount)
        previousFailureCount = signals.totalWorkerFailures

        let isUnderPressure = signals.degradedWorkerCount > 0
            || failureDelta > 0
            || signals.memoryPressure

        if isUnderPressure {
            let pressureFloor = max(minimumLimit, workerCount * 2)
            target = max(pressureFloor, target / 2)
        }

        if signals.selectedThreadIsActive {
            target = min(hardMaximumLimit, target + 1)
        }

        // Always leave headroom for progress while staying bounded.
        target = max(signals.activeTurns + 1, target)
        target = min(hardMaximumLimit, target)
        target = max(minimumLimit, target)

        if target > currentLimit {
            currentLimit = min(target, currentLimit + 8)
        } else if target < currentLimit {
            currentLimit = max(target, currentLimit - 2)
        }

        return currentLimit
    }
}
