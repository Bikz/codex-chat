import Foundation

struct WorkerQueueMetrics: Hashable, Sendable {
    var queueDepth: Int
    var activePermits: Int
}

actor WorkerTurnScheduler {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let maxConcurrentTurnsPerWorker: Int
    private var activePermitsByWorkerID: [RuntimePoolWorkerID: Int] = [:]
    private var waitersByWorkerID: [RuntimePoolWorkerID: [Waiter]] = [:]

    init(maxConcurrentTurnsPerWorker: Int = WorkerTurnScheduler.defaultMaxConcurrentTurnsPerWorker) {
        self.maxConcurrentTurnsPerWorker = max(1, maxConcurrentTurnsPerWorker)
    }

    static var defaultMaxConcurrentTurnsPerWorker: Int {
        let key = "CODEXCHAT_MAX_PARALLEL_TURNS_PER_WORKER"
        if let configured = ProcessInfo.processInfo.environment[key],
           let parsed = Int(configured),
           parsed > 0
        {
            return min(parsed, 64)
        }

        return 3
    }

    func reserve(workerID: RuntimePoolWorkerID) async throws {
        try Task.checkCancellation()

        if canGrantPermit(for: workerID) {
            activePermitsByWorkerID[workerID, default: 0] += 1
            return
        }

        let waiterID = UUID()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waitersByWorkerID[workerID, default: []].append(
                    Waiter(id: waiterID, continuation: continuation)
                )
            }
        } onCancel: {
            Task {
                await self.cancel(waiterID: waiterID, workerID: workerID)
            }
        }

        guard acquired else {
            throw CancellationError()
        }

        if Task.isCancelled {
            release(workerID: workerID)
            throw CancellationError()
        }
    }

    func release(workerID: RuntimePoolWorkerID, permits: Int = 1) {
        let normalizedPermits = max(0, permits)
        guard normalizedPermits > 0 else {
            return
        }

        let current = activePermitsByWorkerID[workerID, default: 0]
        let next = max(0, current - normalizedPermits)
        if next == 0 {
            activePermitsByWorkerID.removeValue(forKey: workerID)
        } else {
            activePermitsByWorkerID[workerID] = next
        }

        promoteWaitersIfPossible(for: workerID)
    }

    func cancelAll() {
        let continuations = waitersByWorkerID.values.flatMap { waiters in
            waiters.map(\.continuation)
        }
        waitersByWorkerID.removeAll(keepingCapacity: false)
        activePermitsByWorkerID.removeAll(keepingCapacity: false)
        continuations.forEach { $0.resume(returning: false) }
    }

    func snapshot() -> [RuntimePoolWorkerID: WorkerQueueMetrics] {
        let workerIDs = Set(activePermitsByWorkerID.keys).union(waitersByWorkerID.keys)
        return workerIDs.reduce(into: [:]) { partialResult, workerID in
            partialResult[workerID] = WorkerQueueMetrics(
                queueDepth: waitersByWorkerID[workerID, default: []].count,
                activePermits: activePermitsByWorkerID[workerID, default: 0]
            )
        }
    }

    private func cancel(waiterID: UUID, workerID: RuntimePoolWorkerID) {
        guard var waiters = waitersByWorkerID[workerID],
              let index = waiters.firstIndex(where: { $0.id == waiterID })
        else {
            return
        }

        let waiter = waiters.remove(at: index)
        if waiters.isEmpty {
            waitersByWorkerID.removeValue(forKey: workerID)
        } else {
            waitersByWorkerID[workerID] = waiters
        }
        waiter.continuation.resume(returning: false)
    }

    private func canGrantPermit(for workerID: RuntimePoolWorkerID) -> Bool {
        activePermitsByWorkerID[workerID, default: 0] < maxConcurrentTurnsPerWorker
    }

    private func promoteWaitersIfPossible(for workerID: RuntimePoolWorkerID) {
        while canGrantPermit(for: workerID) {
            guard var waiters = waitersByWorkerID[workerID], !waiters.isEmpty else {
                return
            }

            let waiter = waiters.removeFirst()
            if waiters.isEmpty {
                waitersByWorkerID.removeValue(forKey: workerID)
            } else {
                waitersByWorkerID[workerID] = waiters
            }

            activePermitsByWorkerID[workerID, default: 0] += 1
            waiter.continuation.resume(returning: true)
        }
    }
}
