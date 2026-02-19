import Foundation

extension AppModel {
    func scheduleSelectedThreadHydration(
        threadID: UUID,
        transitionGeneration: UInt64,
        reason: String
    ) {
        selectedThreadHydrationTask?.cancel()
        selectedThreadHydrationGeneration = selectedThreadHydrationGeneration &+ 1
        let hydrationGeneration = selectedThreadHydrationGeneration

        selectedThreadHydrationTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                if selectedThreadHydrationGeneration == hydrationGeneration {
                    selectedThreadHydrationTask = nil
                }
            }

            do {
                try await refreshFollowUpQueue(threadID: threadID)
                guard !Task.isCancelled else { return }
                guard selectedThreadHydrationGeneration == hydrationGeneration else { return }
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                guard selectedThreadID == threadID else { return }

                await rehydrateThreadTranscript(threadID: threadID)
                guard !Task.isCancelled else { return }
                guard selectedThreadHydrationGeneration == hydrationGeneration else { return }
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                guard selectedThreadID == threadID else { return }

                refreshConversationStateIfSelectedThreadChanged(threadID)
            } catch is CancellationError {
                return
            } catch {
                guard selectedThreadHydrationGeneration == hydrationGeneration else { return }
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                guard selectedThreadID == threadID else { return }
                appendLog(.warning, "Selected-thread hydration failed (\(reason)): \(error.localizedDescription)")
            }
        }
    }
}
