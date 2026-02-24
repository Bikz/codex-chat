import CodexKit
import Foundation

actor RuntimeEventDispatchBridge {
    private enum Constants {
        static let flushIntervalNanoseconds: UInt64 = 12_000_000
        static let maxBatchSize = 192
        static let maxDeliveryChunkSize = 64
    }

    private let handler: @MainActor ([CodexRuntimeEvent]) async -> Void

    private var pendingEvents: [CodexRuntimeEvent] = []
    private var flushTask: Task<Void, Never>?

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
        await deliver(batch: batch)
    }

    func stop() async {
        await flushNow()
        flushTask?.cancel()
        flushTask = nil
        pendingEvents.removeAll(keepingCapacity: false)
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
        var index = 0
        while index < batch.count {
            let nextIndex = min(index + Constants.maxDeliveryChunkSize, batch.count)
            await handler(Array(batch[index ..< nextIndex]))
            index = nextIndex

            if index < batch.count {
                await Task.yield()
            }
        }
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
}
