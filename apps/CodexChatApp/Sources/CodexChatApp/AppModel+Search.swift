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
        Task {
            selectedProjectID = result.projectID
            selectedThreadID = result.threadID
            draftChatProjectID = nil
            detailDestination = .thread
            do {
                try await persistSelection()
                try await refreshThreads()
                try await refreshSkills()
                refreshModsSurface()
                try await refreshFollowUpQueue(threadID: result.threadID)
                refreshConversationState()
            } catch {
                appendLog(.error, "Failed to open search result: \(error.localizedDescription)")
            }
        }
    }
}
