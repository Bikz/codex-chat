import Foundation

actor TurnConcurrencyScheduler {
    enum Priority: Int, Sendable {
        case selected = 0
        case manual = 1
        case queuedAuto = 2
    }

    private struct Waiter {
        let id: UUID
        let threadID: UUID
        let priority: Priority
        let sequence: UInt64
        let continuation: CheckedContinuation<Void, Never>
    }

    private var maxConcurrentTurns: Int
    private var activeThreadIDs: Set<UUID> = []
    private var waiters: [Waiter] = []
    private var sequenceCounter: UInt64 = 0

    init(maxConcurrentTurns: Int) {
        self.maxConcurrentTurns = max(1, maxConcurrentTurns)
    }

    var maxConcurrentLimit: Int {
        maxConcurrentTurns
    }

    var activeCount: Int {
        activeThreadIDs.count
    }

    func updateMaxConcurrentTurns(_ limit: Int) {
        let normalized = max(1, limit)
        guard normalized != maxConcurrentTurns else {
            return
        }

        maxConcurrentTurns = normalized
        promoteWaitersIfPossible()
    }

    func reserve(threadID: UUID, priority: Priority) async throws {
        try Task.checkCancellation()

        if canGrantPermit(for: threadID) {
            activeThreadIDs.insert(threadID)
            return
        }

        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                sequenceCounter = sequenceCounter &+ 1
                let waiter = Waiter(
                    id: waiterID,
                    threadID: threadID,
                    priority: priority,
                    sequence: sequenceCounter,
                    continuation: continuation
                )
                waiters.append(waiter)
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancel(waiterID: waiterID)
            }
        }

        try Task.checkCancellation()
    }

    func release(threadID: UUID) {
        guard activeThreadIDs.remove(threadID) != nil else {
            return
        }

        promoteWaitersIfPossible()
    }

    func cancelAll() {
        let continuations = waiters.map(\.continuation)
        waiters.removeAll(keepingCapacity: false)
        activeThreadIDs.removeAll(keepingCapacity: false)
        continuations.forEach { $0.resume() }
    }

    private func cancel(waiterID: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else {
            return
        }

        let waiter = waiters.remove(at: index)
        waiter.continuation.resume()
    }

    private func canGrantPermit(for threadID: UUID) -> Bool {
        !activeThreadIDs.contains(threadID) && activeThreadIDs.count < maxConcurrentTurns
    }

    private func promoteWaitersIfPossible() {
        while activeThreadIDs.count < maxConcurrentTurns {
            guard let nextIndex = nextReadyWaiterIndex() else {
                break
            }

            let waiter = waiters.remove(at: nextIndex)
            guard !activeThreadIDs.contains(waiter.threadID) else {
                waiter.continuation.resume()
                continue
            }

            activeThreadIDs.insert(waiter.threadID)
            waiter.continuation.resume()
        }
    }

    private func nextReadyWaiterIndex() -> Int? {
        var candidateIndex: Int?
        var candidatePriority = Priority.queuedAuto
        var candidateSequence = UInt64.max

        for (index, waiter) in waiters.enumerated() where !activeThreadIDs.contains(waiter.threadID) {
            if waiter.priority.rawValue < candidatePriority.rawValue {
                candidateIndex = index
                candidatePriority = waiter.priority
                candidateSequence = waiter.sequence
                continue
            }

            if waiter.priority == candidatePriority, waiter.sequence < candidateSequence {
                candidateIndex = index
                candidateSequence = waiter.sequence
            }
        }

        return candidateIndex
    }
}
