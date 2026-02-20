import Foundation

actor RuntimeThreadResolutionCoordinator {
    private struct InFlightEntry {
        let generation: UInt64
        let task: Task<String, Error>
    }

    private var inFlightByThreadID: [UUID: InFlightEntry] = [:]
    private var generationCounter: UInt64 = 0

    func resolve(
        localThreadID: UUID,
        operation: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        if let existing = inFlightByThreadID[localThreadID] {
            return try await existing.task.value
        }

        generationCounter = generationCounter &+ 1
        let generation = generationCounter
        let task = Task<String, Error> {
            try await operation()
        }
        inFlightByThreadID[localThreadID] = InFlightEntry(generation: generation, task: task)

        do {
            let runtimeThreadID = try await task.value
            clearIfCurrent(localThreadID: localThreadID, generation: generation)
            return runtimeThreadID
        } catch {
            clearIfCurrent(localThreadID: localThreadID, generation: generation)
            throw error
        }
    }

    func cancel(localThreadID: UUID) {
        if let existing = inFlightByThreadID.removeValue(forKey: localThreadID) {
            existing.task.cancel()
        }
    }

    func cancelAll() {
        for entry in inFlightByThreadID.values {
            entry.task.cancel()
        }
        inFlightByThreadID.removeAll(keepingCapacity: false)
    }

    private func clearIfCurrent(localThreadID: UUID, generation: UInt64) {
        guard let existing = inFlightByThreadID[localThreadID],
              existing.generation == generation
        else {
            return
        }

        inFlightByThreadID.removeValue(forKey: localThreadID)
    }
}
