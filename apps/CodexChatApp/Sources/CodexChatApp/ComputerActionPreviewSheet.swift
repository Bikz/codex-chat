import CodexChatCore
import CodexChatUI
import SwiftUI

struct ComputerActionPreviewSheet: View {
    @ObservedObject var model: AppModel
    let preview: AppModel.PendingComputerActionPreview

    @Environment(\.dismiss) private var dismiss
    @Environment(\.designTokens) private var tokens

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionCard(
                        title: preview.providerDisplayName,
                        subtitle: preview.artifact.summary
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            statusRow

                            MarkdownMessageView(
                                text: preview.artifact.detailsMarkdown,
                                allowsExternalContent: false
                            )
                            .font(.system(size: tokens.typography.bodySize))
                            .textSelection(.enabled)

                            if let status = model.computerActionStatusMessage,
                               !status.isEmpty
                            {
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(tokens.spacing.medium)
            }
            .navigationTitle("Action Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancelPendingComputerActionPreview()
                        dismiss()
                    }
                    .disabled(model.isComputerActionExecutionInProgress)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(preview.requiresConfirmation ? "Confirm Run" : "Run") {
                        model.confirmPendingComputerActionPreview()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isComputerActionExecutionInProgress)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            badge(text: safetyLabel(for: preview.safetyLevel), tone: .secondary)
            if preview.requiresConfirmation {
                badge(text: "Confirmation Required", tone: .orange)
            } else {
                badge(text: "Read-only", tone: .green)
            }
            Spacer(minLength: 0)
        }
    }

    private func safetyLabel(for level: ComputerActionSafetyLevel) -> String {
        switch level {
        case .readOnly:
            "Read-only"
        case .externallyVisible:
            "Externally Visible"
        case .destructive:
            "File-changing"
        }
    }

    private func badge(text: String, tone: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tone.opacity(0.12), in: Capsule())
            .foregroundStyle(tone)
    }
}
