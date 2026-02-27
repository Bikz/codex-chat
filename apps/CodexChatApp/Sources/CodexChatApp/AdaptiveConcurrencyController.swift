import Foundation

actor AdaptiveConcurrencyController {
    struct Signals: Sendable {
        var queuedTurns: Int
        var workerQueuedTurns: Int
        var activeTurns: Int
        var workerCount: Int
        var degradedWorkerCount: Int
        var totalWorkerFailures: Int
        var selectedThreadIsActive: Bool
        var memoryPressure: Bool
        var rollingP95TTFTMS: Double?
        var eventBacklogPressure: Bool
    }

    private enum Defaults {
        static let maxBasePerWorker = 16
        static let maxTTFTBudgetMS = 15000.0
    }

    private let minimumLimit: Int
    private let hardMaximumLimit: Int
    private let basePerWorker: Int
    private let ttftBudgetMS: Double
    private let backoffMultiplier: Double
    private var currentLimit: Int
    private var previousFailureCount: Int = 0

    init(
        minimumLimit: Int = 2,
        hardMaximumLimit: Int,
        basePerWorker: Int = AdaptiveConcurrencyController.defaultBasePerWorker,
        ttftBudgetMS: Double = AdaptiveConcurrencyController.defaultTTFTBudgetMS,
        backoffMultiplier: Double = AdaptiveConcurrencyController.defaultBackoffMultiplier
    ) {
        self.minimumLimit = max(1, minimumLimit)
        self.hardMaximumLimit = max(self.minimumLimit, hardMaximumLimit)
        self.basePerWorker = max(1, min(basePerWorker, Defaults.maxBasePerWorker))
        self.ttftBudgetMS = max(100, min(ttftBudgetMS, Defaults.maxTTFTBudgetMS))
        self.backoffMultiplier = max(0.1, backoffMultiplier)
        currentLimit = self.minimumLimit
    }

    static var defaultBasePerWorker: Int {
        let key = "CODEXCHAT_ADAPTIVE_CONCURRENCY_BASE_PER_WORKER"
        if let configured = ProcessInfo.processInfo.environment[key],
           let parsed = Int(configured),
           parsed > 0
        {
            return parsed
        }
        return RuntimeConcurrencyHeuristics.recommendedAdaptiveBasePerWorker()
    }

    static var defaultTTFTBudgetMS: Double {
        let key = "CODEXCHAT_ADAPTIVE_CONCURRENCY_TTFT_P95_BUDGET_MS"
        if let configured = ProcessInfo.processInfo.environment[key],
           let parsed = Double(configured),
           parsed.isFinite,
           parsed > 0
        {
            return parsed
        }
        return 2500
    }

    static var defaultBackoffMultiplier: Double {
        let key = "CODEXCHAT_ADAPTIVE_CONCURRENCY_BACKOFF_MULTIPLIER"
        if let configured = ProcessInfo.processInfo.environment[key],
           let parsed = Double(configured),
           parsed.isFinite,
           parsed > 0
        {
            return parsed
        }
        return 1.0
    }

    func nextLimit(signals: Signals) -> Int {
        let workerCount = max(1, signals.workerCount)
        let baselineLimit = min(
            hardMaximumLimit,
            max(minimumLimit, workerCount * basePerWorker)
        )
        var target = baselineLimit

        if signals.queuedTurns > 0 {
            let backlogBoost = min(max(8, baselineLimit), signals.queuedTurns / 2)
            target = min(hardMaximumLimit, baselineLimit + backlogBoost)
        }

        let failureDelta = max(0, signals.totalWorkerFailures - previousFailureCount)
        previousFailureCount = signals.totalWorkerFailures

        let ttftUnderPressure = (signals.rollingP95TTFTMS ?? 0) > ttftBudgetMS
        let workerQueuePressureThreshold = max(2, workerCount)
        let workerQueueUnderPressure = signals.workerQueuedTurns >= workerQueuePressureThreshold
        let isUnderPressure = signals.degradedWorkerCount > 0
            || failureDelta > 0
            || signals.memoryPressure
            || signals.eventBacklogPressure
            || ttftUnderPressure
            || workerQueueUnderPressure

        if isUnderPressure {
            let pressureFloor = max(minimumLimit, workerCount)
            let divisor = max(1.0, 1.0 + backoffMultiplier)
            let reducedTarget = Int((Double(target) / divisor).rounded(.down))
            target = max(pressureFloor, reducedTarget)
            if workerQueueUnderPressure {
                target = max(pressureFloor, min(target, currentLimit - 2))
            }
        }

        if signals.selectedThreadIsActive, !isUnderPressure {
            target = min(hardMaximumLimit, target + 1)
        }

        if !isUnderPressure {
            target = max(signals.activeTurns + 1, target)
        } else {
            let pressureFloor = max(minimumLimit, workerCount)
            let pressureCap = max(pressureFloor, currentLimit - 2)
            target = min(target, pressureCap)
        }
        target = min(hardMaximumLimit, target)
        target = max(minimumLimit, target)

        if target > currentLimit {
            currentLimit = min(target, currentLimit + 4)
        } else if target < currentLimit {
            currentLimit = max(target, currentLimit - 8)
        }

        return currentLimit
    }
}
