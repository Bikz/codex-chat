import Foundation

extension AppModel {
    func startRuntimePoolMetricsLoopIfNeeded() {
        guard runtimePool != nil else {
            runtimePoolSnapshot = .empty
            return
        }
        guard runtimePoolMetricsTask == nil else {
            return
        }

        runtimePoolMetricsTask = Task { [weak self] in
            guard let self else { return }
            await refreshRuntimePoolSnapshot()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else {
                    break
                }
                await refreshRuntimePoolSnapshot()
            }
        }
    }

    func stopRuntimePoolMetricsLoop() {
        runtimePoolMetricsTask?.cancel()
        runtimePoolMetricsTask = nil
    }

    func refreshRuntimePoolSnapshot() async {
        guard let runtimePool else {
            runtimePoolSnapshot = .empty
            return
        }

        let snapshot = await runtimePool.snapshot()
        runtimePoolSnapshot = snapshot
        if runtimeStatus == .connected {
            scheduleAdaptiveConcurrencyRefresh(reason: "runtime pool metrics tick")
        }
    }
}
