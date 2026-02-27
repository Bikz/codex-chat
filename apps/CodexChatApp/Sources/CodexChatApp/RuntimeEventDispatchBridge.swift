import CodexKit
import Foundation

struct RuntimeEventBacklogSnapshot: Hashable, Sendable {
    var saturatedFlushRate: Double
    var slowDeliveryRate: Double
    var isUnderPressure: Bool
}

actor RuntimeEventDispatchBridge {
    private enum Constants {
        static let flushIntervalNanoseconds: UInt64 = 12_000_000
        static let maxBatchSize = 192
        static let maxDeliveryChunkSize = 64
        static let pressureHistoryLimit = 40
        static let slowDeliveryThresholdMS = 24.0
        static let saturatedFlushPressureThreshold = 0.25
        static let slowDeliveryPressureThreshold = 0.20
    }

    private let handler: @MainActor ([CodexRuntimeEvent]) async -> Void

    private var pendingEvents: [CodexRuntimeEvent] = []
    private var flushTask: Task<Void, Never>?
    private var recentSaturatedFlushes: [Bool] = []
    private var recentSlowDeliveries: [Bool] = []
    private let clock = ContinuousClock()

    init(handler: @escaping @MainActor ([CodexRuntimeEvent]) async -> Void) {
        self.handler = handler
    }

    func enqueue(_ event: CodexRuntimeEvent) async {
        if coalescePendingEventIfPossible(event) {
            if pendingEvents.count >= Constants.maxBatchSize {
                await flushNow()
                return
            }

            scheduleFlushIfNeeded()
            return
        }

        pendingEvents.append(event)

        if shouldFlushImmediately(event) || pendingEvents.count >= Constants.maxBatchSize {
            await flushNow()
            return
        }

        scheduleFlushIfNeeded()
    }

    func flushNow() async {
        flushTask?.cancel()
        flushTask = nil

        guard !pendingEvents.isEmpty else {
            return
        }

        let batch = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        recordSaturatedFlush(batch.count >= Constants.maxBatchSize)
        await deliver(batch: batch)
    }

    func stop() async {
        await flushNow()
        flushTask?.cancel()
        flushTask = nil
        pendingEvents.removeAll(keepingCapacity: false)
        recentSaturatedFlushes.removeAll(keepingCapacity: false)
        recentSlowDeliveries.removeAll(keepingCapacity: false)
    }

    func backlogSnapshot() -> RuntimeEventBacklogSnapshot {
        let saturatedRate = trueRate(recentSaturatedFlushes)
        let slowRate = trueRate(recentSlowDeliveries)
        return RuntimeEventBacklogSnapshot(
            saturatedFlushRate: saturatedRate,
            slowDeliveryRate: slowRate,
            isUnderPressure: saturatedRate >= Constants.saturatedFlushPressureThreshold
                || slowRate >= Constants.slowDeliveryPressureThreshold
        )
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil else {
            return
        }

        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.flushIntervalNanoseconds)
            guard let self, !Task.isCancelled else {
                return
            }

            await flushNow()
        }
    }

    private func shouldFlushImmediately(_ event: CodexRuntimeEvent) -> Bool {
        switch event {
        case .turnCompleted:
            true
        case .approvalRequested:
            true
        case let .action(action):
            action.method == "runtime/terminated"
                || action.method == "turn/start/error"
                || action.method == "turn/error"
        case .assistantMessageDelta:
            false
        case .commandOutputDelta:
            false
        case .followUpSuggestions:
            false
        case .fileChangesUpdated:
            false
        case .threadStarted:
            false
        case .turnStarted:
            false
        case .accountUpdated:
            false
        case .accountLoginCompleted:
            false
        }
    }

    private func deliver(batch: [CodexRuntimeEvent]) async {
        let deliveryStartedAt = clock.now
        var index = 0
        while index < batch.count {
            let nextIndex = min(index + Constants.maxDeliveryChunkSize, batch.count)
            await handler(Array(batch[index ..< nextIndex]))
            index = nextIndex

            if index < batch.count {
                await Task.yield()
            }
        }

        let duration = deliveryStartedAt.duration(to: clock.now)
        recordSlowDelivery(duration.seconds * 1000 >= Constants.slowDeliveryThresholdMS)
    }

    private func coalescePendingEventIfPossible(_ event: CodexRuntimeEvent) -> Bool {
        guard let lastEvent = pendingEvents.last else {
            return false
        }

        switch (lastEvent, event) {
        case let (
            .assistantMessageDelta(lastDelta),
            .assistantMessageDelta(nextDelta)
        ) where lastDelta.threadID == nextDelta.threadID
            && lastDelta.turnID == nextDelta.turnID
            && lastDelta.itemID == nextDelta.itemID
            && lastDelta.channel == nextDelta.channel
            && lastDelta.stage == nextDelta.stage:
            pendingEvents[pendingEvents.count - 1] = .assistantMessageDelta(
                RuntimeAssistantMessageDelta(
                    itemID: lastDelta.itemID,
                    threadID: lastDelta.threadID,
                    turnID: lastDelta.turnID,
                    delta: lastDelta.delta + nextDelta.delta,
                    channel: lastDelta.channel,
                    stage: lastDelta.stage
                )
            )
            return true

        case let (.commandOutputDelta(lastDelta), .commandOutputDelta(nextDelta))
            where lastDelta.itemID == nextDelta.itemID
            && lastDelta.threadID == nextDelta.threadID
            && lastDelta.turnID == nextDelta.turnID:
            pendingEvents[pendingEvents.count - 1] = .commandOutputDelta(
                RuntimeCommandOutputDelta(
                    itemID: lastDelta.itemID,
                    threadID: lastDelta.threadID,
                    turnID: lastDelta.turnID,
                    delta: lastDelta.delta + nextDelta.delta
                )
            )
            return true

        default:
            return false
        }
    }

    private func recordSaturatedFlush(_ saturated: Bool) {
        recentSaturatedFlushes.append(saturated)
        if recentSaturatedFlushes.count > Constants.pressureHistoryLimit {
            recentSaturatedFlushes.removeFirst(recentSaturatedFlushes.count - Constants.pressureHistoryLimit)
        }
    }

    private func recordSlowDelivery(_ slow: Bool) {
        recentSlowDeliveries.append(slow)
        if recentSlowDeliveries.count > Constants.pressureHistoryLimit {
            recentSlowDeliveries.removeFirst(recentSlowDeliveries.count - Constants.pressureHistoryLimit)
        }
    }

    private func trueRate(_ values: [Bool]) -> Double {
        guard !values.isEmpty else {
            return 0
        }
        let trueCount = values.reduce(0) { partialResult, value in
            partialResult + (value ? 1 : 0)
        }
        return Double(trueCount) / Double(values.count)
    }
}

private extension Duration {
    var seconds: Double {
        let components = components
        return Double(components.seconds) + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
