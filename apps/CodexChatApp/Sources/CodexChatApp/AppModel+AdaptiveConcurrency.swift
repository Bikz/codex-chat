import Foundation

extension AppModel {
    func scheduleAdaptiveConcurrencyRefresh(reason: String) {
        adaptiveConcurrencyRefreshTask?.cancel()

        let runtimePool = runtimePool
        let scheduler = turnConcurrencyScheduler
        let controller = adaptiveConcurrencyController
        let queuedTurns = followUpQueueByThreadID.values.reduce(0) { partialResult, items in
            partialResult + items.count
        }
        let selectedThreadIsActive = isSelectedThreadWorking
        let memoryPressure = ProcessInfo.processInfo.thermalState == .serious
            || ProcessInfo.processInfo.thermalState == .critical
        let performanceSignals = runtimePerformanceSignals
        let eventDispatchBridge = runtimeEventDispatchBridge

        adaptiveConcurrencyRefreshTask = Task { [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
            guard !Task.isCancelled else {
                return
            }

            let snapshot = await runtimePool?.snapshot() ?? .empty
            let degradedWorkers = snapshot.workers.count { worker in
                worker.health == .degraded || worker.health == .restarting
            }
            let failureCount = snapshot.workers.reduce(0) { partialResult, worker in
                partialResult + worker.failureCount
            }
            let activeTurns = max(activeTurnThreadIDs.count, snapshot.totalInFlightTurns)
            let performanceSnapshot = await performanceSignals.snapshot()
            let eventBacklogSnapshot = await eventDispatchBridge.backlogSnapshot()

            let limit = await controller.nextLimit(
                signals: .init(
                    queuedTurns: queuedTurns,
                    workerQueuedTurns: snapshot.totalQueuedTurns,
                    activeTurns: activeTurns,
                    workerCount: max(1, snapshot.configuredWorkerCount),
                    degradedWorkerCount: degradedWorkers,
                    totalWorkerFailures: failureCount,
                    selectedThreadIsActive: selectedThreadIsActive,
                    memoryPressure: memoryPressure,
                    rollingP95TTFTMS: performanceSnapshot.rollingP95TTFTMS,
                    eventBacklogPressure: eventBacklogSnapshot.isUnderPressure
                )
            )
            await scheduler.updateMaxConcurrentTurns(limit)
            adaptiveTurnConcurrencyLimit = limit
            rollingTTFTP95MS = performanceSnapshot.rollingP95TTFTMS

            appendLog(.debug, "Adaptive turn limit updated (\(reason)): \(limit)")

            await PerformanceTracer.shared.record(
                name: "runtime.adaptiveConcurrency.limit",
                durationMS: Double(limit),
                metadata: [
                    "reason": reason,
                    "ttftP95MS": performanceSnapshot.rollingP95TTFTMS.map { String(format: "%.1f", $0) } ?? "na",
                    "eventBacklogPressure": eventBacklogSnapshot.isUnderPressure ? "1" : "0",
                    "workerQueuedTurns": "\(snapshot.totalQueuedTurns)",
                ]
            )
        }
    }
}
