import Foundation

struct PlanExecutionState: Hashable, Sendable {
    var completedTaskIDs: Set<String>
    var inFlightTaskIDs: Set<String>
    var failedTaskIDs: Set<String>

    init(
        completedTaskIDs: Set<String> = [],
        inFlightTaskIDs: Set<String> = [],
        failedTaskIDs: Set<String> = []
    ) {
        self.completedTaskIDs = completedTaskIDs
        self.inFlightTaskIDs = inFlightTaskIDs
        self.failedTaskIDs = failedTaskIDs
    }
}

enum PlanSchedulerError: LocalizedError, Sendable {
    case cycleDetected([String])

    var errorDescription: String? {
        switch self {
        case let .cycleDetected(taskIDs):
            "Plan has a dependency cycle involving: \(taskIDs.joined(separator: ", "))."
        }
    }
}

struct PlanScheduler: Sendable {
    let document: PlanDocument

    init(document: PlanDocument) throws {
        self.document = document
        try Self.validateAcyclic(document: document)
    }

    func nextUnblockedBatch(
        state: PlanExecutionState,
        preferredBatchSize: Int,
        multiAgentEnabled: Bool
    ) -> [PlanTask] {
        let unresolvedTasks = document.tasks.filter { task in
            !state.completedTaskIDs.contains(task.id)
                && !state.inFlightTaskIDs.contains(task.id)
                && !state.failedTaskIDs.contains(task.id)
        }

        let unblocked = unresolvedTasks.filter { task in
            task.dependencies.allSatisfy { dependencyID in
                state.completedTaskIDs.contains(dependencyID)
            }
        }

        let batchLimit = multiAgentEnabled ? max(1, preferredBatchSize) : 1
        return Array(unblocked.prefix(batchLimit))
    }

    func isComplete(state: PlanExecutionState) -> Bool {
        document.tasks.allSatisfy { state.completedTaskIDs.contains($0.id) }
    }

    private static func validateAcyclic(document: PlanDocument) throws {
        let tasks = document.tasks
        let taskIDs = tasks.map(\.id)
        var incomingCount: [String: Int] = [:]
        var outgoing: [String: [String]] = [:]

        for taskID in taskIDs {
            incomingCount[taskID] = 0
            outgoing[taskID] = []
        }

        for task in tasks {
            for dependencyID in task.dependencies {
                outgoing[dependencyID, default: []].append(task.id)
                incomingCount[task.id, default: 0] += 1
            }
        }

        var queue = taskIDs.filter { incomingCount[$0] == 0 }
        var processedCount = 0

        while !queue.isEmpty {
            let current = queue.removeFirst()
            processedCount += 1

            for downstream in outgoing[current, default: []] {
                let remaining = (incomingCount[downstream] ?? 0) - 1
                incomingCount[downstream] = remaining
                if remaining == 0 {
                    queue.append(downstream)
                }
            }
        }

        guard processedCount == tasks.count else {
            let cycleTaskIDs = incomingCount
                .filter { $0.value > 0 }
                .keys
                .sorted()
            throw PlanSchedulerError.cycleDetected(cycleTaskIDs)
        }
    }
}
