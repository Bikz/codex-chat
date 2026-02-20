import CodexKit
import Foundation

actor TurnPersistenceScheduler {
    struct Job: Sendable {
        let context: AppModel.ActiveTurnContext
        let completion: RuntimeTurnCompletion
    }

    private let maxConcurrentJobs: Int
    private let handler: @MainActor (Job) async -> Void

    private var runningJobs = 0
    private var pendingJobs: [Job] = []

    init(
        maxConcurrentJobs: Int,
        handler: @escaping @MainActor (Job) async -> Void
    ) {
        self.maxConcurrentJobs = max(1, maxConcurrentJobs)
        self.handler = handler
    }

    func enqueue(context: AppModel.ActiveTurnContext, completion: RuntimeTurnCompletion) {
        pendingJobs.append(Job(context: context, completion: completion))
        launchIfPossible()
    }

    func cancelQueuedJobs() {
        pendingJobs.removeAll(keepingCapacity: false)
    }

    private func launchIfPossible() {
        while runningJobs < maxConcurrentJobs, !pendingJobs.isEmpty {
            runningJobs += 1
            let job = pendingJobs.removeFirst()
            Task { [weak self] in
                await self?.run(job)
            }
        }
    }

    private func run(_ job: Job) async {
        await handler(job)
        runningJobs = max(0, runningJobs - 1)
        launchIfPossible()
    }
}
