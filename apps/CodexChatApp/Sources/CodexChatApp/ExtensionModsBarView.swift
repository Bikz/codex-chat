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

    private var promptBookInitialEntries: [AppModel.PromptBookEntry] {
        model.promptBookEntriesFromState()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(modsBarTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if model.hasModsBarQuickSwitchChoices {
                    Menu {
                        ForEach(model.modsBarQuickSwitchOptions) { option in
                            Button {
                                model.activateModsBarQuickSwitchOption(option)
                            } label: {
                                HStack {
                                    Text("\(option.mod.definition.manifest.name) (\(option.scope.label))")
                                    if option.isSelected {
                                        Spacer(minLength: 6)
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "rectangle.3.group.bubble.left")
                            .font(.caption)
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Switch active mod")
                    .accessibilityLabel("Switch active mod")
                }

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
                } else if model.isPromptBookModsBarActiveForSelectedThread {
                    PromptBookInlineEditor(
                        model: model,
                        initialEntries: promptBookInitialEntries
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

private struct PromptBookInlineEditor: View {
    private struct EditablePrompt: Identifiable, Hashable {
        let id: String
        var title: String
        var text: String
    }

    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    let initialEntries: [AppModel.PromptBookEntry]

    @State private var prompts: [EditablePrompt]
    @State private var newTitle = ""
    @State private var newText = ""
    @State private var refreshTask: Task<Void, Never>?

    private let maxPrompts = 12

    init(model: AppModel, initialEntries: [AppModel.PromptBookEntry]) {
        self.model = model
        self.initialEntries = initialEntries
        _prompts = State(initialValue: initialEntries.map {
            EditablePrompt(id: $0.id, title: $0.title, text: $0.text)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: tokens.spacing.small) {
                Text("Prompt Library")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("New prompt title", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: $newText)
                        .font(.body)
                        .frame(minHeight: 70)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(tokens.surfaces.baseOpacity))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity))
                        )
                        .accessibilityLabel("New prompt text")

                    HStack(spacing: 8) {
                        Text("\(prompts.count)/\(maxPrompts) prompts")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Add Prompt") {
                            addPrompt()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isAddDisabled)
                    }
                }
                .padding(10)
                .tokenCard(style: .panel, radius: tokens.radius.small, strokeOpacity: 0.06)

                ForEach(Array(prompts.indices), id: \.self) { index in
                    promptCard(index: index)
                }
            }
            .padding(.bottom, tokens.spacing.small)
        }
        .onAppear {
            reloadPrompts(from: initialEntries)
        }
        .onChange(of: initialEntries) { _, nextValue in
            reloadPrompts(from: nextValue)
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    private var isAddDisabled: Bool {
        newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || prompts.count >= maxPrompts
    }

    private func promptCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "Prompt title",
                text: Binding(
                    get: { prompts[index].title },
                    set: { prompts[index].title = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)

            TextEditor(
                text: Binding(
                    get: { prompts[index].text },
                    set: { prompts[index].text = $0 }
                )
            )
            .font(.body)
            .frame(minHeight: 90)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(tokens.surfaces.baseOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity))
            )

            HStack(spacing: 8) {
                Button("Send") {
                    sendPrompt(at: index)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Save") {
                    savePrompt(at: index)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer(minLength: 0)

                Button("Delete", role: .destructive) {
                    deletePrompt(at: index)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .tokenCard(style: .panel, radius: tokens.radius.small, strokeOpacity: 0.06)
    }

    private func addPrompt() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        model.upsertPromptBookEntryInline(index: nil, title: title, text: text)
        newTitle = ""
        newText = ""
        scheduleRefreshFromModel()
    }

    private func savePrompt(at index: Int) {
        guard prompts.indices.contains(index) else { return }
        let prompt = prompts[index]
        model.upsertPromptBookEntryInline(index: index, title: prompt.title, text: prompt.text)
        scheduleRefreshFromModel()
    }

    private func deletePrompt(at index: Int) {
        guard prompts.indices.contains(index) else { return }
        model.deletePromptBookEntryInline(index: index)
        scheduleRefreshFromModel()
    }

    private func sendPrompt(at index: Int) {
        guard prompts.indices.contains(index) else { return }
        let text = prompts[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.composerText = text
        model.sendMessage()
    }

    private func reloadPrompts(from entries: [AppModel.PromptBookEntry]) {
        prompts = entries.map {
            EditablePrompt(id: $0.id, title: $0.title, text: $0.text)
        }
    }

    private func scheduleRefreshFromModel() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            await model.refreshModsBarForSelectedThread()
            reloadPrompts(from: model.promptBookEntriesFromState())
        }
    }
}
