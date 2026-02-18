import CodexChatCore
import CodexChatUI
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
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
        .sheet(isPresented: $model.isProjectSettingsVisible) {
            ProjectSettingsSheet(model: model)
        }
        .onAppear {
            model.onAppear()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.medium) {
            TextField(
                "Search threads and archived messages",
                text: Binding(
                    get: { model.searchQuery },
                    set: { model.updateSearchQuery($0) }
                )
            )
            .textFieldStyle(.roundedBorder)

            if !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchSurface
                    .frame(minHeight: 120, maxHeight: 220)
            }

            HStack {
                Text("Projects")
                    .font(.system(size: tokens.typography.titleSize, weight: .semibold))
                Spacer()

                Button(action: model.openProjectFolder) {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)

                Button(action: model.showProjectSettings) {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .disabled(model.selectedProjectID == nil)
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

            if let projectStatusMessage = model.projectStatusMessage {
                Text(projectStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(tokens.spacing.medium)
        .background(Color(hex: tokens.palette.panelHex).opacity(0.6))
    }

    @ViewBuilder
    private var searchSurface: some View {
        switch model.searchState {
        case .idle:
            EmptyStateView(
                title: "Search ready",
                message: "Results appear as you type.",
                systemImage: "magnifyingglass"
            )
        case .loading:
            LoadingStateView(title: "Searching archives…")
        case .failed(let message):
            ErrorStateView(title: "Search unavailable", message: message, actionLabel: "Retry") {
                model.updateSearchQuery(model.searchQuery)
            }
        case .loaded(let results) where results.isEmpty:
            EmptyStateView(
                title: "No results",
                message: "Try a different keyword.",
                systemImage: "magnifyingglass"
            )
        case .loaded(let results):
            List(results) { result in
                Button {
                    model.selectSearchResult(result)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.source.capitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(result.excerpt)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: tokens.radius.medium))
        }
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
                message: "Open a folder to start organizing chats.",
                systemImage: "folder"
            )
        case .loaded:
            List(model.projects, selection: Binding(get: {
                model.selectedProjectID
            }, set: { selection in
                model.selectProject(selection)
            })) { project in
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                    Text(project.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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

                Button("Reveal Chat File") {
                    model.revealSelectedThreadArchiveInFinder()
                }
                .buttonStyle(.bordered)
                .disabled(model.selectedThreadID == nil)
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

private struct ProjectTrustBanner: View {
    let onTrust: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)

            Text("Project is untrusted. Read-only behavior is recommended until you trust this folder.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Trust") {
                onTrust()
            }
            .buttonStyle(.borderedProminent)

            Button("Settings") {
                onSettings()
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ProjectSettingsSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Project Settings")
                .font(.title3.weight(.semibold))

            if let project = model.selectedProject {
                LabeledContent("Name") { Text(project.name) }
                LabeledContent("Path") {
                    Text(project.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Trust") {
                    Text(project.trustState.rawValue.capitalized)
                        .foregroundStyle(project.trustState == .trusted ? .green : .orange)
                }

                HStack {
                    Button("Trust Project") {
                        model.trustSelectedProject()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(project.trustState == .trusted)

                    Button("Mark Untrusted") {
                        model.untrustSelectedProject()
                    }
                    .buttonStyle(.bordered)
                    .disabled(project.trustState == .untrusted)
                }
            } else {
                Text("Select a project first.")
                    .foregroundStyle(.secondary)
            }

            if let status = model.projectStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    model.closeProjectSettings()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 300)
    }
}
