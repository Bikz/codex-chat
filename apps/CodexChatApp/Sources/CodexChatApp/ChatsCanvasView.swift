import CodexChatCore
import CodexChatUI
import SwiftUI

struct ChatsCanvasView: View {
    @ObservedObject var model: AppModel
    @Binding var isInsertMemorySheetVisible: Bool
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(spacing: 0) {
            if shouldShowChatSetup {
                ChatSetupView(model: model)
            } else {
                if !model.isSelectedProjectTrusted, model.selectedProjectID != nil {
                    ProjectTrustBanner(
                        onTrust: model.trustSelectedProject,
                        onSettings: model.showProjectSettings
                    )
                    .padding(.horizontal, tokens.spacing.medium)
                    .padding(.top, tokens.spacing.small)
                }

                runtimeAwareConversationSurface

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    FollowUpQueueView(model: model)
                    composerSurface

                    if let followUpStatus = model.followUpStatusMessage {
                        Text(followUpStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, tokens.spacing.medium)
                    }
                }

                if model.isShellWorkspaceVisible {
                    Divider()
                    ShellWorkspaceDrawer(model: model)
                        .frame(height: 280)
                        .background(tokens.materials.panelMaterial.material)
                }
            }
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            if !shouldShowChatSetup {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.openReviewChanges()
                    } label: {
                        Label("Review Changes", systemImage: "doc.text.magnifyingglass")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Review pending changes")
                    .help("Review changes")
                    .disabled(!model.canReviewChanges)

                    Button {
                        model.revealSelectedThreadArchiveInFinder()
                    } label: {
                        Label("Reveal Chat File", systemImage: "doc.text")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Reveal chat archive in Finder")
                    .help("Reveal latest chat archive")
                    .disabled(model.selectedThreadID == nil)

                    Button {
                        model.toggleShellWorkspace()
                    } label: {
                        Label("Shell Workspace", systemImage: "terminal")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Toggle shell workspace")
                    .help("Toggle shell workspace")
                }
            }
        }
    }

    private var shouldShowChatSetup: Bool {
        if case .installCodex? = model.runtimeIssue {
            return true
        }

        if model.runtimeStatus != .connected {
            return true
        }

        if model.runtimeIssue != nil {
            return true
        }

        if !model.isSignedInForRuntime {
            return true
        }

        if model.selectedProjectID == nil {
            return true
        }

        if model.selectedThreadID == nil, !model.hasActiveDraftChatForSelectedProject {
            return true
        }

        return false
    }

    private var composerSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            ComposerControlBar(model: model)

            Divider()
                .opacity(0.55)

            HStack(alignment: .bottom, spacing: tokens.spacing.small) {
                Button {
                    isInsertMemorySheetVisible = true
                } label: {
                    Image(systemName: "brain")
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Insert memory snippet")
                .help("Insert memory snippet")
                .disabled(model.selectedProjectID == nil)

                TextField(composerPlaceholder, text: $model.composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: tokens.typography.bodySize + 0.5, weight: .medium))
                    .lineLimit(1 ... 6)
                    .padding(.vertical, 10)
                    .onSubmit {
                        model.submitComposerWithQueuePolicy()
                    }
                    .accessibilityLabel("Message input")

                Button {
                    model.submitComposerWithQueuePolicy()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(model.canSubmitComposer ? Color.blue : Color.blue.opacity(0.35))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send message")
                .help("Send")
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canSubmitComposer)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tokens.materials.panelMaterial.material, in: RoundedRectangle(cornerRadius: tokens.radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: tokens.radius.large)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .padding(.horizontal, tokens.spacing.medium)
        .padding(.vertical, tokens.spacing.small)
    }

    private var composerPlaceholder: String {
        if case .installCodex? = model.runtimeIssue {
            return "Install Codex CLI to enable runtime turns…"
        }
        if model.runtimeStatus == .starting {
            return "Connecting to Codex runtime…"
        }
        return "Ask CodexChat to do something…"
    }

    @ViewBuilder
    private var runtimeAwareConversationSurface: some View {
        if case .installCodex? = model.runtimeIssue {
            InstallCodexGuidanceView()
        } else if let runtimeIssue = model.runtimeIssue {
            ErrorStateView(
                title: "Runtime unavailable",
                message: runtimeIssue.message,
                actionLabel: "Restart Runtime"
            ) {
                model.restartRuntime()
            }
        } else {
            switch model.conversationState {
            case .idle:
                EmptyStateView(
                    title: "No active thread",
                    message: "Choose or create a thread to start chatting.",
                    systemImage: "bubble.left.and.bubble.right"
                )
            case .loading:
                LoadingStateView(title: "Preparing conversation…")
            case let .failed(message):
                ErrorStateView(title: "Conversation unavailable", message: message, actionLabel: "Retry") {
                    model.retryLoad()
                }
            case let .loaded(entries) where entries.isEmpty:
                EmptyStateView(
                    title: "Thread is empty",
                    message: "Use the composer below to send the first message.",
                    systemImage: "text.cursor"
                )
            case let .loaded(entries):
                ScrollViewReader { proxy in
                    List(entries) { entry in
                        switch entry {
                        case let .message(message):
                            MessageRow(message: message, tokens: tokens)
                                .padding(.vertical, tokens.spacing.xSmall)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 0,
                                        leading: tokens.spacing.medium,
                                        bottom: 0,
                                        trailing: tokens.spacing.medium
                                    )
                                )
                        case let .actionCard(card):
                            ActionCardRow(card: card)
                                .padding(.vertical, tokens.spacing.xSmall)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 0,
                                        leading: tokens.spacing.medium,
                                        bottom: 0,
                                        trailing: tokens.spacing.medium
                                    )
                                )
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onAppear {
                        scrollTranscriptToBottom(entries: entries, proxy: proxy, animated: false)
                    }
                    .onChange(of: entries.last?.id) { _, _ in
                        scrollTranscriptToBottom(entries: entries, proxy: proxy, animated: true)
                    }
                }
            }
        }
    }

    private func scrollTranscriptToBottom(
        entries: [TranscriptEntry],
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let lastID = entries.last?.id else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct ComposerControlBar: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @State private var isCustomModelSheetVisible = false
    @State private var customModelDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(model.modelPresets, id: \.self) { preset in
                        Button(preset) {
                            model.setDefaultModel(preset)
                        }
                    }

                    Divider()

                    Button("Custom…") {
                        customModelDraft = model.defaultModel
                        isCustomModelSheetVisible = true
                    }
                } label: {
                    controlChip(
                        title: "Model",
                        value: model.defaultModel,
                        systemImage: "cpu",
                        tint: Color(hex: tokens.palette.accentHex),
                        minWidth: 180
                    )
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Model")
                .help("Select model")

                Menu {
                    ForEach(AppModel.ReasoningLevel.allCases, id: \.self) { level in
                        Button(level.title) {
                            model.setDefaultReasoning(level)
                        }
                    }
                } label: {
                    controlChip(
                        title: "Reasoning",
                        value: model.defaultReasoning.title,
                        systemImage: "brain.head.profile",
                        tint: Color.blue.opacity(0.9),
                        minWidth: 140
                    )
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Reasoning")
                .help("Select reasoning effort")

                Menu {
                    ForEach(ProjectWebSearchMode.allCases, id: \.self) { mode in
                        Button(webSearchLabel(mode)) {
                            model.setDefaultWebSearch(mode)
                        }
                    }
                } label: {
                    controlChip(
                        title: "Web",
                        value: webSearchLabel(model.defaultWebSearch),
                        systemImage: "globe",
                        tint: webSearchTint(model.defaultWebSearch),
                        minWidth: 110
                    )
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Web search mode")
                .help("Select web search mode")

                Spacer()
            }

            if model.isDefaultWebSearchClampedForSelectedProject() {
                Text("Web mode is clamped by project safety policy for this thread.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isCustomModelSheetVisible) {
            CustomModelSheet(
                modelID: $customModelDraft,
                onCancel: {
                    isCustomModelSheetVisible = false
                },
                onSave: {
                    model.setDefaultModel(customModelDraft)
                    isCustomModelSheetVisible = false
                }
            )
        }
    }

    private func controlChip(
        title: String,
        value: String,
        systemImage: String,
        tint: Color,
        minWidth: CGFloat
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 14, height: 14)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minWidth: minWidth, alignment: .leading)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func webSearchLabel(_ mode: ProjectWebSearchMode) -> String {
        switch mode {
        case .cached:
            "Cached"
        case .live:
            "Live"
        case .disabled:
            "Disabled"
        }
    }

    private func webSearchTint(_ mode: ProjectWebSearchMode) -> Color {
        switch mode {
        case .cached:
            .secondary
        case .live:
            Color(hex: tokens.palette.accentHex)
        case .disabled:
            .orange
        }
    }
}

private struct CustomModelSheet: View {
    @Binding var modelID: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Model")
                .font(.title3.weight(.semibold))

            TextField("Model ID", text: $modelID)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
