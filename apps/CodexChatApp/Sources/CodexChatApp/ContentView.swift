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
            case .loaded(let messages) where messages.isEmpty:
                EmptyStateView(
                    title: "Thread is empty",
                    message: "Use the composer below to send the first message.",
                    systemImage: "text.cursor"
                )
            case .loaded(let messages):
                List(messages) { message in
                    VStack(alignment: .leading, spacing: tokens.spacing.xSmall) {
                        Text(message.role.rawValue.capitalized)
                            .font(.system(size: tokens.typography.captionSize, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(message.text)
                            .font(.system(size: tokens.typography.bodySize))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, tokens.spacing.xSmall)
                }
                .listStyle(.plain)
            }

            Divider()

            HStack(spacing: tokens.spacing.small) {
                TextField("Ask CodexChat to do something…", text: $model.composerText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button("Send") {
                    model.sendMessage()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: tokens.palette.accentHex))
                .disabled(model.selectedThreadID == nil)
            }
            .padding(tokens.spacing.medium)
            .background(Color(hex: tokens.palette.panelHex).opacity(0.5))
        }
        .navigationTitle("Conversation")
    }
}
