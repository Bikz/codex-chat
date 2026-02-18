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

                    if let selectedSkill = model.selectedSkillForComposer {
                        HStack(spacing: 8) {
                            Label("Using \(selectedSkill.skill.name)", systemImage: "wand.and.stars")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Clear") {
                                model.clearSelectedSkillForComposer()
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Clear selected skill")

                            Spacer()
                        }
                        .padding(.horizontal, tokens.spacing.medium)
                    }

                    HStack(alignment: .bottom, spacing: tokens.spacing.small) {
                        Menu {
                            if model.enabledSkillsForSelectedProject.isEmpty {
                                Text("No enabled skills")
                            } else {
                                ForEach(model.enabledSkillsForSelectedProject) { item in
                                    Button(item.skill.name) {
                                        model.selectSkillForComposer(item)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(.secondary)
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 22, height: 22)
                        }
                        .menuStyle(.borderlessButton)
                        .accessibilityLabel("Insert skill trigger")
                        .help("Insert skill trigger")
                        .disabled(model.enabledSkillsForSelectedProject.isEmpty)

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
                            .font(.system(size: tokens.typography.bodySize))
                            .lineLimit(1 ... 6)
                            .padding(.vertical, 10)
                            .onSubmit {
                                model.submitComposerWithQueuePolicy()
                            }
                            .accessibilityLabel("Message input")

                        Button {
                            model.submitComposerWithQueuePolicy()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color(hex: tokens.palette.accentHex))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Send message")
                        .help("Send")
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(!model.canSubmitComposer)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(tokens.materials.panelMaterial.material, in: RoundedRectangle(cornerRadius: tokens.radius.large))
                    .overlay(
                        RoundedRectangle(cornerRadius: tokens.radius.large)
                            .strokeBorder(Color.primary.opacity(0.05))
                    )
                    .padding(.horizontal, tokens.spacing.medium)
                    .padding(.vertical, tokens.spacing.small)

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

        if model.selectedProjectID == nil || model.selectedThreadID == nil {
            return true
        }

        return false
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
                    .onChange(of: entries.last?.id) { _ in
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
