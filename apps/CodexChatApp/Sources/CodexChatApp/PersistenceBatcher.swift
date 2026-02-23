import CodexKit
import Foundation

actor PersistenceBatcher {
    enum Durability: Sendable {
        case immediate
        case batched
    }

    struct Configuration: Sendable {
        let maxPendingJobs: Int
        let flushThreshold: Int
        let flushIntervalNanoseconds: UInt64

        init(
            maxPendingJobs: Int = 256,
            flushThreshold: Int = 8,
            flushIntervalNanoseconds: UInt64 = 300_000_000
        ) {
            self.maxPendingJobs = max(1, maxPendingJobs)
            self.flushThreshold = max(1, flushThreshold)
            self.flushIntervalNanoseconds = max(1, flushIntervalNanoseconds)
        }

        static let `default` = Configuration()
    }

    struct Job: Sendable {
        let context: AppModel.ActiveTurnContext
        let completion: RuntimeTurnCompletion
    }

    private let configuration: Configuration
    private let handler: @MainActor ([Job]) async -> Void
    private var pendingJobs: [Job] = []
    private var flushTask: Task<Void, Never>?

    init(
        configuration: Configuration = .default,
        handler: @escaping @MainActor ([Job]) async -> Void
    ) {
        self.configuration = configuration
        self.handler = handler
    }

    func enqueue(
        context: AppModel.ActiveTurnContext,
        completion: RuntimeTurnCompletion,
        durability: Durability
    ) async {
        if pendingJobs.count >= configuration.maxPendingJobs {
            await flushNow()
        }

        pendingJobs.append(Job(context: context, completion: completion))
        switch durability {
        case .immediate:
            await flushNow()
        case .batched:
            if pendingJobs.count >= configuration.flushThreshold {
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

        let flushDelayNanoseconds = configuration.flushIntervalNanoseconds
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: flushDelayNanoseconds)
            guard let self else {
                return
            }
            await flushNow()
        }
    }
}
