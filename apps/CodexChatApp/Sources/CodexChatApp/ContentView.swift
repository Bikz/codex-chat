import CodexChatCore
import CodexChatUI
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            conversationCanvas
        }
        .background(Color(hex: tokens.palette.backgroundHex))
        .sheet(isPresented: $model.isDiagnosticsVisible) {
            DiagnosticsView(
                runtimeStatus: model.runtimeStatus,
                logs: model.logs,
                onClose: model.closeDiagnostics
            )
        }
        .onAppear {
            model.onAppear()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.medium) {
            HStack {
                Text("Projects")
                    .font(.system(size: tokens.typography.titleSize, weight: .semibold))
                Spacer()
                Button(action: model.createProject) {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            projectsSurface
                .frame(minHeight: 180)

            HStack {
                Text("Threads")
                    .font(.system(size: tokens.typography.titleSize, weight: .semibold))
                Spacer()
                Button(action: model.createThread) {
                    Label("New Thread", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(model.selectedProjectID == nil)
            }

            threadsSurface

            Spacer()
        }
        .padding(tokens.spacing.medium)
        .background(Color(hex: tokens.palette.panelHex).opacity(0.6))
    }

    @ViewBuilder
    private var projectsSurface: some View {
        switch model.projectsState {
        case .idle, .loading:
            LoadingStateView(title: "Loading projects…")
        case .failed(let message):
            ErrorStateView(title: "Couldn’t load projects", message: message, actionLabel: "Retry") {
                model.retryLoad()
            }
        case .loaded(let projects) where projects.isEmpty:
            EmptyStateView(
                title: "No projects yet",
                message: "Create a project to start organizing chats.",
                systemImage: "folder"
            )
        case .loaded:
            List(model.projects, selection: Binding(get: {
                model.selectedProjectID
            }, set: { selection in
                model.selectProject(selection)
            })) { project in
                Text(project.name)
                    .tag(project.id)
            }
            .clipShape(RoundedRectangle(cornerRadius: tokens.radius.medium))
        }
    }

    @ViewBuilder
    private var threadsSurface: some View {
        switch model.threadsState {
        case .idle:
            EmptyStateView(
                title: "Select a project",
                message: "Threads appear after you select a project.",
                systemImage: "sidebar.left"
            )
        case .loading:
            LoadingStateView(title: "Loading threads…")
        case .failed(let message):
            ErrorStateView(title: "Couldn’t load threads", message: message, actionLabel: "Retry") {
                model.retryLoad()
            }
        case .loaded(let threads) where threads.isEmpty:
            EmptyStateView(
                title: "No threads yet",
                message: "Create a thread to start the conversation.",
                systemImage: "bubble.left.and.bubble.right"
            )
        case .loaded:
            List(model.threads, selection: Binding(get: {
                model.selectedThreadID
            }, set: { selection in
                model.selectThread(selection)
            })) { thread in
                Text(thread.title)
                    .tag(thread.id)
            }
            .clipShape(RoundedRectangle(cornerRadius: tokens.radius.medium))
        }
    }

    private var conversationCanvas: some View {
        VStack(spacing: 0) {
            runtimeAwareConversationSurface

            Divider()

            HStack(spacing: tokens.spacing.small) {
                TextField(composerPlaceholder, text: $model.composerText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button("Send") {
                    model.sendMessage()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: tokens.palette.accentHex))
                .disabled(!model.canSendMessages)
            }
            .padding(tokens.spacing.medium)
            .background(Color(hex: tokens.palette.panelHex).opacity(0.5))
        }
        .navigationTitle("Conversation")
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
            case .failed(let message):
                ErrorStateView(title: "Conversation unavailable", message: message, actionLabel: "Retry") {
                    model.retryLoad()
                }
            case .loaded(let entries) where entries.isEmpty:
                EmptyStateView(
                    title: "Thread is empty",
                    message: "Use the composer below to send the first message.",
                    systemImage: "text.cursor"
                )
            case .loaded(let entries):
                List(entries) { entry in
                    switch entry {
                    case .message(let message):
                        MessageRow(message: message, tokens: tokens)
                            .padding(.vertical, tokens.spacing.xSmall)
                            .listRowSeparator(.hidden)
                    case .actionCard(let card):
                        ActionCardRow(card: card)
                            .padding(.vertical, tokens.spacing.xSmall)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let tokens: DesignTokens

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.xSmall) {
            Text(message.role.rawValue.capitalized)
                .font(.system(size: tokens.typography.captionSize, weight: .medium))
                .foregroundStyle(.secondary)
            Text(message.text)
                .font(.system(size: tokens.typography.bodySize))
                .textSelection(.enabled)
        }
    }
}

private struct ActionCardRow: View {
    let card: ActionCard
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(card.detail)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.callout.weight(.semibold))
                Text(card.method)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct InstallCodexGuidanceView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            Text("Install Codex CLI")
                .font(.headline)

            Text("CodexChat needs the local `codex` binary to run app-server turns.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link("Open Codex install docs", destination: URL(string: "https://developers.openai.com/codex/cli")!)
                .buttonStyle(.borderedProminent)

            Text("After installation, use Developer → Toggle Diagnostics and press Restart Runtime.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
