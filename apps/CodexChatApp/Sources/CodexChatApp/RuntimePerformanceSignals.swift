import Foundation
import os

struct RuntimePerformanceSnapshot: Hashable, Sendable {
    var rollingP95TTFTMS: Double?
    var sampleCount: Int
}

actor RuntimePerformanceSignals {
    private struct DispatchRecord: Sendable {
        let startedAt: Date
        let signpostID: OSSignpostID
    }

    private let maxSampleCount: Int
    private var dispatchRecordByThreadID: [UUID: DispatchRecord] = [:]
    private var ttftSamplesMS: [Double] = []

    init(maxSampleCount: Int = 180) {
        self.maxSampleCount = max(1, maxSampleCount)
    }

    func recordDispatchStart(
        threadID: UUID,
        localTurnID: UUID,
        startedAt: Date = Date()
    ) {
        let signpostID = RuntimeConcurrencySignpost.makeID()
        RuntimeConcurrencySignpost.begin(
            "TTFT",
            id: signpostID,
            detail: "thread=\(threadID.uuidString) turn=\(localTurnID.uuidString)"
        )
        dispatchRecordByThreadID[threadID] = DispatchRecord(
            startedAt: startedAt,
            signpostID: signpostID
        )
    }

    func recordFirstTokenIfNeeded(
        threadID: UUID,
        receivedAt: Date = Date()
    ) {
        guard let dispatchRecord = dispatchRecordByThreadID.removeValue(forKey: threadID) else {
            return
        }
        let latencyMS = max(0, receivedAt.timeIntervalSince(dispatchRecord.startedAt) * 1000)
        RuntimeConcurrencySignpost.end(
            "TTFT",
            id: dispatchRecord.signpostID,
            detail: "status=ok ms=\(String(format: "%.1f", latencyMS))"
        )
        appendSample(latencyMS)
        Task {
            await PerformanceTracer.shared.record(
                name: "runtime.ttft",
                durationMS: latencyMS
            )
        }
    }

    func markTurnCompleted(threadID: UUID) {
        guard let dispatchRecord = dispatchRecordByThreadID.removeValue(forKey: threadID) else {
            return
        }
        RuntimeConcurrencySignpost.end(
            "TTFT",
            id: dispatchRecord.signpostID,
            detail: "status=no-first-token"
        )
    }

    func snapshot() -> RuntimePerformanceSnapshot {
        RuntimePerformanceSnapshot(
            rollingP95TTFTMS: computeP95(),
            sampleCount: ttftSamplesMS.count
        )
    }

    func reset() {
        for dispatchRecord in dispatchRecordByThreadID.values {
            RuntimeConcurrencySignpost.end(
                "TTFT",
                id: dispatchRecord.signpostID,
                detail: "status=reset"
            )
        }
        dispatchRecordByThreadID.removeAll(keepingCapacity: false)
        ttftSamplesMS.removeAll(keepingCapacity: false)
    }

    private func appendSample(_ value: Double) {
        ttftSamplesMS.append(value)
        if ttftSamplesMS.count > maxSampleCount {
            ttftSamplesMS.removeFirst(ttftSamplesMS.count - maxSampleCount)
        }
    }

    private func computeP95() -> Double? {
        guard !ttftSamplesMS.isEmpty else {
            return nil
        }

        let sorted = ttftSamplesMS.sorted()
        let index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
        return sorted[index]
    }
}
