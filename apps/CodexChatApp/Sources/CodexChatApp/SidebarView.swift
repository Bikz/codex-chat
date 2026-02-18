import CodexChatUI
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.medium) {
            Picker("Navigation", selection: $model.navigationSection) {
                Text("Chats").tag(AppModel.NavigationSection.chats)
                Text("Skills").tag(AppModel.NavigationSection.skills)
                Text("Memory").tag(AppModel.NavigationSection.memory)
                Text("Mods").tag(AppModel.NavigationSection.mods)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Projects")
                    .font(.system(size: tokens.typography.titleSize, weight: .semibold))
                Spacer()

                Button(action: model.openProjectFolder) {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)

                Button(action: model.showProjectSettings) {
                    Label("Project Settings", systemImage: "slider.horizontal.3")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Project settings")
                .help("Project settings")
                .disabled(model.selectedProjectID == nil)
            }

            projectsSurface
                .frame(minHeight: 180)

            switch model.navigationSection {
            case .chats:
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
            case .skills:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Skills are enabled per selected project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Select a project, then manage installed skills in the main panel.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            case .memory:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Memory is stored as editable markdown in the project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Use the Memory panel to manage `memory/*.md` and control auto-summaries.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            case .mods:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mods customize the UI with user-owned token overrides.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Use the Mods panel to enable global and per-project themes.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let projectStatusMessage = model.projectStatusMessage {
                Text(projectStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(tokens.spacing.medium)
        .background(tokens.materials.panelMaterial.material)
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
        case let .failed(message):
            ErrorStateView(title: "Search unavailable", message: message, actionLabel: "Retry") {
                model.updateSearchQuery(model.searchQuery)
            }
        case let .loaded(results) where results.isEmpty:
            EmptyStateView(
                title: "No results",
                message: "Try a different keyword.",
                systemImage: "magnifyingglass"
            )
        case let .loaded(results):
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
        case let .failed(message):
            ErrorStateView(title: "Couldn’t load projects", message: message, actionLabel: "Retry") {
                model.retryLoad()
            }
        case let .loaded(projects) where projects.isEmpty:
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
        case let .failed(message):
            ErrorStateView(title: "Couldn’t load threads", message: message, actionLabel: "Retry") {
                model.retryLoad()
            }
        case let .loaded(threads) where threads.isEmpty:
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
}
