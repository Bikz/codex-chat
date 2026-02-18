import CodexChatUI
import CodexKit
import SwiftUI

@MainActor
struct ModChangesReviewSheet: View {
    @ObservedObject var model: AppModel
    let review: AppModel.PendingModReview
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review Mod Changes")
                .font(.title3.weight(.semibold))

            Text(review.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Changed files")
                .font(.headline)

            List(review.changes, id: \.self) { change in
                VStack(alignment: .leading, spacing: 6) {
                    Text(change.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let diff = change.diff, !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(diff)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(12)
                    } else {
                        Text("No diff available.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: tokens.radius.medium))

            if !review.canRevert {
                Text("Revert is unavailable because a snapshot could not be captured for this turn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Revert Mod Changes") {
                    model.revertPendingModReview()
                }
                .buttonStyle(.bordered)
                .disabled(!review.canRevert || model.isModReviewDecisionInProgress)

                Button("Accept Changes") {
                    model.acceptPendingModReview()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isModReviewDecisionInProgress)

                Spacer()

                Button("Open Skills & Mods") {
                    model.openSkillsAndMods()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 560)
    }
}
