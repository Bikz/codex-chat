import CodexChatCore
import Foundation

extension AppModel {
    func updateSearchQuery(_ query: String) {
        searchQuery = query
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchState = .idle
            return
        }

        guard let chatSearchRepository else {
            searchState = .failed("Search index is unavailable.")
            return
        }

        searchState = .loading
        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                if Task.isCancelled { return }

                let results = try await chatSearchRepository.search(query: trimmed, projectID: nil, limit: 50)
                if Task.isCancelled { return }
                searchState = .loaded(results)
            } catch is CancellationError {
                return
            } catch {
                searchState = .failed(error.localizedDescription)
                appendLog(.error, "Search failed: \(error.localizedDescription)")
            }
        }
    }

    func selectSearchResult(_ result: ChatSearchResult) {
        let previousProjectID = selectedProjectID
        selectedProjectID = result.projectID
        selectedThreadID = result.threadID
        draftChatProjectID = nil
        detailDestination = .thread
        refreshConversationState()

        let transitionGeneration = beginSelectionTransition()
        let task = Task { [weak self] in
            guard let self else { return }
            let span = await PerformanceTracer.shared.begin(
                name: "thread.selectSearchResult",
                metadata: [
                    "threadID": result.threadID.uuidString,
                    "projectID": result.projectID.uuidString,
                ]
            )
            defer {
                Task {
                    await PerformanceTracer.shared.end(span)
                }
                finishSelectionTransition(transitionGeneration)
            }

            selectedProjectID = result.projectID
            selectedThreadID = result.threadID
            draftChatProjectID = nil
            detailDestination = .thread
            do {
                try await persistSelection()
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                try await refreshThreads()
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                scheduleSelectedThreadHydration(
                    threadID: result.threadID,
                    transitionGeneration: transitionGeneration,
                    reason: "selectSearchResult"
                )
                guard isCurrentSelectionTransition(transitionGeneration) else { return }
                refreshConversationStateIfSelectedThreadChanged(result.threadID)
                scheduleProjectSecondarySurfaceRefresh(
                    transitionGeneration: transitionGeneration,
                    targetProjectID: result.projectID,
                    projectContextChanged: previousProjectID != result.projectID,
                    reason: "selectSearchResult"
                )
            } catch {
                appendLog(.error, "Failed to open search result: \(error.localizedDescription)")
            }
        }
        registerSelectionTransitionTask(task, generation: transitionGeneration)
    }
}
