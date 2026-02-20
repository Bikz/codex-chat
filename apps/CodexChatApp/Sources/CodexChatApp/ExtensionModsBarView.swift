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

    private var personalNotesEditorInitialText: String {
        model.personalNotesEditorText(from: model.selectedExtensionModsBarState?.markdown)
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
                } else if model.isPersonalNotesModsBarActiveForSelectedThread {
                    PersonalNotesInlineEditor(
                        model: model,
                        initialText: personalNotesEditorInitialText
                    )
                    .padding(.horizontal, tokens.spacing.medium)
                    .padding(.vertical, tokens.spacing.small)
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

private struct PersonalNotesInlineEditor: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    let initialText: String

    @State private var text: String
    @State private var lastSubmittedText: String
    @State private var autosaveTask: Task<Void, Never>?

    init(model: AppModel, initialText: String) {
        self.model = model
        self.initialText = initialText
        _text = State(initialValue: initialText)
        _lastSubmittedText = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.small) {
            Text("Thread Notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 220)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(tokens.surfaces.baseOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity))
                )
                .onChange(of: text) { _, nextValue in
                    scheduleAutosave(for: nextValue)
                }
                .onChange(of: initialText) { _, nextValue in
                    syncFromModel(nextValue)
                }
                .accessibilityLabel("Personal notes editor")

            HStack(spacing: 8) {
                Text("Autosaves as you type.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Clear Note") {
                    text = ""
                    scheduleAutosave(for: "", immediate: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .onDisappear {
            flushAutosaveOnDisappear()
        }
    }

    private func syncFromModel(_ nextValue: String) {
        // Keep local edits stable while we wait for autosave to flush.
        guard text == lastSubmittedText else { return }
        guard nextValue != text else { return }
        text = nextValue
        lastSubmittedText = nextValue
    }

    private func scheduleAutosave(for nextValue: String, immediate: Bool = false) {
        guard nextValue != lastSubmittedText else { return }
        autosaveTask?.cancel()
        let pendingValue = nextValue
        autosaveTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            guard !Task.isCancelled else { return }
            model.upsertPersonalNotesInline(pendingValue)
            lastSubmittedText = pendingValue
        }
    }

    private func flushAutosaveOnDisappear() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard text != lastSubmittedText else { return }
        model.upsertPersonalNotesInline(text)
        lastSubmittedText = text
    }
}
