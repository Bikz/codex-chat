import CodexChatUI
import SwiftUI

struct ExtensionModsBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    private var modsBarTitle: String {
        model.activeModsBarSlot?.title
            ?? model.selectedExtensionModsBarState?.title
            ?? "Mods bar"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(modsBarTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let updatedAt = model.selectedExtensionModsBarState?.updatedAt {
                    Text(updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, tokens.spacing.medium)
            .padding(.vertical, tokens.spacing.small)

            Divider()

            Group {
                if model.selectedThreadID == nil {
                    EmptyStateView(
                        title: "No thread selected",
                        message: "Select a thread to view modsBar content.",
                        systemImage: "sidebar.right"
                    )
                    .padding(tokens.spacing.medium)
                } else if !model.isModsBarAvailableForSelectedThread {
                    EmptyStateView(
                        title: "Install a Mods bar mod",
                        message: "No active mod exposes modsBar content for this thread. Open Skills & Mods > Mods to install or enable one.",
                        systemImage: "puzzlepiece.extension"
                    )
                    .padding(tokens.spacing.medium)
                } else if let state = model.selectedExtensionModsBarState {
                    ScrollView {
                        VStack(alignment: .leading, spacing: tokens.spacing.small) {
                            MarkdownMessageView(
                                text: state.markdown,
                                allowsExternalContent: model.isSelectedProjectTrusted
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if !state.actions.isEmpty {
                                Divider()
                                    .padding(.top, tokens.spacing.xSmall)

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(state.actions) { action in
                                        Button(action.label) {
                                            model.performModsBarAction(action)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                }
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel("Mods bar actions")
                            }
                        }
                        .padding(.horizontal, tokens.spacing.medium)
                        .padding(.vertical, tokens.spacing.small)
                    }
                } else {
                    LoadingStateView(title: "Waiting for extension output…")
                        .padding(tokens.spacing.medium)
                }
            }
        }
        .background(tokens.materials.panelMaterial.material)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Extension modsBar")
    }
}
