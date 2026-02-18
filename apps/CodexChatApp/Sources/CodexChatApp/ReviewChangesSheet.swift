import CodexChatUI
import SwiftUI

struct ReviewChangesSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Changes")
                .font(.title3.weight(.semibold))

            if model.selectedThreadChanges.isEmpty {
                EmptyStateView(
                    title: "No changes to review",
                    message: "Run a turn that produces file changes, then review here.",
                    systemImage: "doc.text.magnifyingglass"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(model.selectedThreadChanges.enumerated()), id: \.offset) { _, change in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(change.kind): \(change.path)")
                                    .font(.callout.weight(.semibold))

                                if let diff = change.diff, !diff.isEmpty {
                                    Text(diff)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }

            HStack {
                Button("Revert") {
                    model.revertReviewChanges()
                }
                .buttonStyle(.bordered)
                .disabled(model.selectedThreadChanges.isEmpty)

                Button("Accept") {
                    model.acceptReviewChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedThreadChanges.isEmpty)

                Spacer()

                Button("Close") {
                    model.closeReviewChanges()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 480)
    }
}
