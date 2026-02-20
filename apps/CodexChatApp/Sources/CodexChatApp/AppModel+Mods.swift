import CodexChatCore
import Foundation

extension AppModel {
    func acceptPendingModReview() {
        guard let review = pendingModReview else { return }
        pendingModReview = nil
        isModReviewDecisionInProgress = false

        if let snapshot = activeModSnapshotByThreadID.removeValue(forKey: review.threadID) {
            ModEditSafety.discard(snapshot: snapshot)
        }

        appendLog(.info, "Accepted mod changes for thread \(review.threadID.uuidString)")
        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: review.threadID,
                    method: "mods/accepted",
                    title: "Mod changes accepted",
                    detail: "Approved \(review.changes.count) mod-related change(s)."
                )
            ),
            to: review.threadID
        )
        requestAutoDrain(reason: "mod review accepted")
    }

    func revertPendingModReview() {
        guard let review = pendingModReview else { return }
        guard let snapshot = activeModSnapshotByThreadID[review.threadID] else {
            modStatusMessage = "Revert is unavailable (no snapshot captured)."
            return
        }

        isModReviewDecisionInProgress = true
        Task {
            defer { isModReviewDecisionInProgress = false }

            do {
                try ModEditSafety.restore(from: snapshot)
                pendingModReview = nil
                activeModSnapshotByThreadID.removeValue(forKey: review.threadID)
                refreshModsSurface()
                appendLog(.warning, "Reverted mod changes for thread \(review.threadID.uuidString)")
                appendEntry(
                    .actionCard(
                        ActionCard(
                            threadID: review.threadID,
                            method: "mods/reverted",
                            title: "Mod changes reverted",
                            detail: "Restored mod snapshot from \(snapshot.createdAt.formatted())."
                        )
                    ),
                    to: review.threadID
                )
                requestAutoDrain(reason: "mod review reverted")
            } catch {
                modStatusMessage = "Failed to revert mod changes: \(error.localizedDescription)"
                appendLog(.error, "Revert mod changes failed: \(error.localizedDescription)")
            }
        }
    }
}
