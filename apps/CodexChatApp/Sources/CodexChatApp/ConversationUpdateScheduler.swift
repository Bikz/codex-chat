import CodexKit
import Foundation

@MainActor
final class ConversationUpdateScheduler {
    struct BatchItem: Equatable {
        let threadID: UUID
        let itemID: String
        let delta: String
        let channel: RuntimeAssistantMessageChannel
        let stage: String?

        init(
            threadID: UUID,
            itemID: String,
            delta: String,
            channel: RuntimeAssistantMessageChannel = .finalResponse,
            stage: String? = nil
        ) {
            self.threadID = threadID
            self.itemID = itemID
            self.delta = delta
            self.channel = channel
            self.stage = stage
        }
    }

    private struct DeltaKey: Hashable {
        let threadID: UUID
        let itemID: String
        let channel: RuntimeAssistantMessageChannel
        let stage: String?
    }

    private enum Constants {
        static let baseIntervalNanoseconds: UInt64 = 33_000_000
        static let burstIntervalNanoseconds: UInt64 = 50_000_000
        static let burstByteThreshold = 4096
        static let burstItemThreshold = 8
    }

    private let clock = ContinuousClock()
    private let flushHandler: @MainActor ([BatchItem]) -> Void

    private var pendingByKey: [DeltaKey: String] = [:]
    private var insertionOrder: [DeltaKey] = []
    private var flushTask: Task<Void, Never>?
    private var currentIntervalNanoseconds: UInt64 = Constants.baseIntervalNanoseconds
    private var belowBurstThresholdSince: ContinuousClock.Instant?

    init(flushHandler: @escaping @MainActor ([BatchItem]) -> Void) {
        self.flushHandler = flushHandler
    }

    var currentFlushIntervalMilliseconds: Int {
        Int(currentIntervalNanoseconds / 1_000_000)
    }

    func enqueue(
        delta: String,
        threadID: UUID,
        itemID: String,
        channel: RuntimeAssistantMessageChannel = .finalResponse,
        stage: String? = nil
    ) {
        guard !delta.isEmpty else {
            return
        }

        let key = DeltaKey(
            threadID: threadID,
            itemID: itemID,
            channel: channel,
            stage: stage?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if pendingByKey[key] == nil {
            insertionOrder.append(key)
        }
        pendingByKey[key, default: ""].append(delta)

        updateAdaptiveInterval()
        scheduleFlushIfNeeded()
    }

    func flushImmediately() {
        flushTask?.cancel()
        flushTask = nil
        flushPendingDeltas()
    }

    func invalidate() {
        flushTask?.cancel()
        flushTask = nil
        pendingByKey.removeAll(keepingCapacity: false)
        insertionOrder.removeAll(keepingCapacity: false)
        currentIntervalNanoseconds = Constants.baseIntervalNanoseconds
        belowBurstThresholdSince = nil
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil else {
            return
        }

        let interval = currentIntervalNanoseconds
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: interval)
            guard let self, !Task.isCancelled else {
                return
            }
            flushPendingDeltas()
        }
    }

    private func flushPendingDeltas() {
        flushTask?.cancel()
        flushTask = nil

        guard !pendingByKey.isEmpty else {
            updateAdaptiveInterval()
            return
        }

        var batch: [BatchItem] = []
        batch.reserveCapacity(insertionOrder.count)
        for key in insertionOrder {
            guard let delta = pendingByKey[key], !delta.isEmpty else {
                continue
            }
            batch.append(
                BatchItem(
                    threadID: key.threadID,
                    itemID: key.itemID,
                    delta: delta,
                    channel: key.channel,
                    stage: key.stage
                )
            )
        }

        pendingByKey.removeAll(keepingCapacity: true)
        insertionOrder.removeAll(keepingCapacity: true)
        updateAdaptiveInterval()

        if !batch.isEmpty {
            flushHandler(batch)
        }

        if !pendingByKey.isEmpty {
            scheduleFlushIfNeeded()
        }
    }

    private func updateAdaptiveInterval() {
        let pendingBytes = pendingByKey.values.reduce(into: 0) { partialResult, delta in
            partialResult += delta.utf8.count
        }
        let pendingItemCount = pendingByKey.count
        let isBursting = pendingBytes > Constants.burstByteThreshold
            || pendingItemCount > Constants.burstItemThreshold

        if isBursting {
            currentIntervalNanoseconds = Constants.burstIntervalNanoseconds
            belowBurstThresholdSince = nil
            return
        }

        guard currentIntervalNanoseconds == Constants.burstIntervalNanoseconds else {
            return
        }

        let now = clock.now
        if let thresholdStart = belowBurstThresholdSince {
            if now - thresholdStart >= .seconds(1) {
                currentIntervalNanoseconds = Constants.baseIntervalNanoseconds
                belowBurstThresholdSince = nil
            }
        } else {
            belowBurstThresholdSince = now
        }
    }
}
