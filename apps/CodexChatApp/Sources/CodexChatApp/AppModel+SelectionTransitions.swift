import Foundation

@MainActor
private var selectionTransitionTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

@MainActor
private var selectionTransitionGenerations: [ObjectIdentifier: UInt64] = [:]

extension AppModel {
    @MainActor
    func beginSelectionTransition() -> UInt64 {
        let key = ObjectIdentifier(self)
        selectionTransitionTasks[key]?.cancel()
        let generation = (selectionTransitionGenerations[key] ?? 0) + 1
        selectionTransitionGenerations[key] = generation
        return generation
    }

    @MainActor
    func registerSelectionTransitionTask(_ task: Task<Void, Never>, generation: UInt64) {
        let key = ObjectIdentifier(self)
        guard selectionTransitionGenerations[key] == generation else {
            task.cancel()
            return
        }
        selectionTransitionTasks[key] = task
    }

    @MainActor
    func isCurrentSelectionTransition(_ generation: UInt64) -> Bool {
        selectionTransitionGenerations[ObjectIdentifier(self)] == generation
    }

    @MainActor
    func finishSelectionTransition(_ generation: UInt64) {
        let key = ObjectIdentifier(self)
        guard selectionTransitionGenerations[key] == generation else {
            return
        }
        selectionTransitionTasks[key] = nil
    }
}
