import CodexChatUI
import SwiftUI

struct ExtensionInspectorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    private var inspectorTitle: String {
        model.activeRightInspectorSlot?.title
            ?? model.selectedExtensionInspectorState?.title
            ?? "Inspector"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(inspectorTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let updatedAt = model.selectedExtensionInspectorState?.updatedAt {
                    Text(updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, tokens.spacing.medium)
            .padding(.vertical, tokens.spacing.small)

            Divider()

            Group {
                if let state = model.selectedExtensionInspectorState {
                    ScrollView {
                        MarkdownMessageView(
                            text: state.markdown,
                            allowsExternalContent: model.isSelectedProjectTrusted
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, tokens.spacing.medium)
                        .padding(.vertical, tokens.spacing.small)
                    }
                } else if model.selectedThreadID == nil {
                    EmptyStateView(
                        title: "No thread selected",
                        message: "Select a thread to view extension output.",
                        systemImage: "sidebar.right"
                    )
                    .padding(tokens.spacing.medium)
                } else {
                    LoadingStateView(title: "Waiting for extension output…")
                        .padding(tokens.spacing.medium)
                }
            }
        }
        .background(tokens.materials.panelMaterial.material)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Extension inspector")
    }
}
