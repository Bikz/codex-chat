import CodexChatUI
import SwiftUI

struct PendingApprovalsInboxSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.pendingApprovalSummaries.isEmpty {
                    EmptyStateView(
                        title: "No pending approvals",
                        message: "All approvals are resolved.",
                        systemImage: "checkmark.seal"
                    )
                } else {
                    List(model.pendingApprovalSummaries) { summary in
                        HStack(spacing: 10) {
                            Image(systemName: summary.isUnscoped ? "questionmark.circle" : "bubble.left.and.exclamationmark.bubble.right")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(summary.title)
                                    .font(.body.weight(.semibold))
                                Text(summary.count == 1 ? "1 pending request" : "\(summary.count) pending requests")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button(summary.isUnscoped ? "Review" : "Open") {
                                if let threadID = summary.threadID {
                                    model.selectThread(threadID)
                                }
                                model.closeApprovalInbox()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Pending Approvals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        model.closeApprovalInbox()
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 300)
    }
}
