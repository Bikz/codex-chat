import CodexKit
import Foundation

actor PersistenceBatcher {
    enum Durability: Sendable {
        case immediate
        case batched
    }

    struct Job: Sendable {
        let context: AppModel.ActiveTurnContext
        let completion: RuntimeTurnCompletion
    }

    private enum Constants {
        static let maxPendingJobs = 256
        static let flushThreshold = 8
        static let flushIntervalNanoseconds: UInt64 = 300_000_000
    }

    private let handler: @MainActor ([Job]) async -> Void
    private var pendingJobs: [Job] = []
    private var flushTask: Task<Void, Never>?

    init(handler: @escaping @MainActor ([Job]) async -> Void) {
        self.handler = handler
    }

    func enqueue(
        context: AppModel.ActiveTurnContext,
        completion: RuntimeTurnCompletion,
        durability: Durability
    ) async {
        if pendingJobs.count >= Constants.maxPendingJobs {
            await flushNow()
        }

        pendingJobs.append(Job(context: context, completion: completion))
        switch durability {
        case .immediate:
            await flushNow()
        case .batched:
            if pendingJobs.count >= Constants.flushThreshold {
                await flushNow()
            } else {
                scheduleFlushIfNeeded()
            }
        }
    }

    func flushNow() async {
        flushTask?.cancel()
        flushTask = nil

        guard !pendingJobs.isEmpty else {
            return
        }

        let jobs = pendingJobs
        pendingJobs.removeAll(keepingCapacity: true)
        await handler(jobs)
    }

    func shutdown() async {
        await flushNow()
        flushTask?.cancel()
        flushTask = nil
        pendingJobs.removeAll(keepingCapacity: false)
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil else {
            return
        }

        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.flushIntervalNanoseconds)
            guard let self else {
                return
            }
            await flushNow()
        }
    }
}
