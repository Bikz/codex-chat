import CodexChatCore
import CodexChatUI
import CodexKit
import CodexSkills
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @State private var isInstallSkillSheetVisible = false
    @State private var isInsertMemorySheetVisible = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            detailSurface
        }
        .background(Color(hex: tokens.palette.backgroundHex))
        .sheet(isPresented: $model.isDiagnosticsVisible) {
            DiagnosticsView(
                runtimeStatus: model.runtimeStatus,
                logs: model.logs,
                onClose: model.closeDiagnostics
            )
        }
        .sheet(isPresented: $model.isAPIKeyPromptVisible) {
            APIKeyLoginSheet(model: model)
        }
        .sheet(isPresented: $model.isProjectSettingsVisible) {
            ProjectSettingsSheet(model: model)
        }
        .sheet(isPresented: $model.isReviewChangesVisible) {
            ReviewChangesSheet(model: model)
        }
        .sheet(isPresented: $isInstallSkillSheetVisible) {
            InstallSkillSheet(model: model, isPresented: $isInstallSkillSheetVisible)
        }
        .sheet(isPresented: $isInsertMemorySheetVisible) {
            MemorySnippetInsertSheet(model: model, isPresented: $isInsertMemorySheetVisible)
        }
        .sheet(item: Binding(get: {
            model.pendingModReview
        }, set: { _ in })) { review in
            ModChangesReviewSheet(model: model, review: review)
                .interactiveDismissDisabled(true)
        }
        .sheet(item: Binding(get: {
            model.activeApprovalRequest
        }, set: { _ in })) { request in
            ApprovalRequestSheet(model: model, request: request)
                .interactiveDismissDisabled(model.isApprovalDecisionInProgress)
        }
        .onAppear {
            model.onAppear()
        }
        .onChange(of: model.navigationSection) { newValue in
            switch newValue {
            case .skills:
                model.refreshSkillsSurface()
            case .mods:
                model.refreshModsSurface()
            case .chats, .memory:
                break
            }
        }
    }

    @ViewBuilder
    private var detailSurface: some View {
        switch model.navigationSection {
        case .chats:
            conversationCanvas
        case .skills:
            skillsCanvas
        case .memory:
            MemoryCanvas(model: model)
        case .mods:
            ModsCanvas(model: model)
        }
    }

    private var sidebar: some View {
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

    private var conversationCanvas: some View {
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
                    if let selectedSkill = model.selectedSkillForComposer {
                        HStack(spacing: 8) {
                            Label("Using \(selectedSkill.skill.name)", systemImage: "wand.and.stars")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Clear") {
                                model.clearSelectedSkillForComposer()
                            }
                            .buttonStyle(.borderless)

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
                                .frame(width: 22, height: 22)
                        }
                        .menuStyle(.borderlessButton)
                        .help("Insert skill trigger")
                        .disabled(model.enabledSkillsForSelectedProject.isEmpty)

                        Button {
                            isInsertMemorySheetVisible = true
                        } label: {
                            Image(systemName: "brain")
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.borderless)
                        .help("Insert memory snippet")
                        .disabled(model.selectedProjectID == nil)

                        TextField(composerPlaceholder, text: $model.composerText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1 ... 6)
                            .padding(.vertical, 10)

                        Button {
                            model.sendMessage()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color(hex: tokens.palette.accentHex))
                        }
                        .buttonStyle(.borderless)
                        .help("Send")
                        .disabled(!model.canSendMessages)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(tokens.materials.panelMaterial.material, in: RoundedRectangle(cornerRadius: tokens.radius.large))
                    .overlay(
                        RoundedRectangle(cornerRadius: tokens.radius.large)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
                    .padding(.horizontal, tokens.spacing.medium)
                    .padding(.vertical, tokens.spacing.small)
                }

                if model.isLogsDrawerVisible {
                    Divider()
                    ThreadLogsDrawer(entries: model.selectedThreadLogs)
                        .frame(height: 180)
                        .background(tokens.materials.panelMaterial.material)
                }
            }
        }
        .navigationTitle("Conversation")
        .toolbar {
            if !shouldShowChatSetup {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.openReviewChanges()
                    } label: {
                        Label("Review Changes", systemImage: "doc.text.magnifyingglass")
                            .labelStyle(.iconOnly)
                    }
                    .help("Review changes")
                    .disabled(!model.canReviewChanges)

                    Button {
                        model.revealSelectedThreadArchiveInFinder()
                    } label: {
                        Label("Reveal Chat File", systemImage: "doc.text")
                            .labelStyle(.iconOnly)
                    }
                    .help("Reveal latest chat archive")
                    .disabled(model.selectedThreadID == nil)

                    Button {
                        model.toggleLogsDrawer()
                    } label: {
                        Label("Terminal / Logs", systemImage: "terminal")
                            .labelStyle(.iconOnly)
                    }
                    .help("Toggle terminal/logs drawer")
                }
            }
        }
    }

    private var shouldShowChatSetup: Bool {
        if model.navigationSection != .chats {
            return false
        }

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
                                .listRowInsets(EdgeInsets(top: 0, leading: tokens.spacing.medium, bottom: 0, trailing: tokens.spacing.medium))
                        case let .actionCard(card):
                            ActionCardRow(card: card)
                                .padding(.vertical, tokens.spacing.xSmall)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 0, leading: tokens.spacing.medium, bottom: 0, trailing: tokens.spacing.medium))
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

    private var skillsCanvas: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Skills")
                    .font(.system(size: tokens.typography.titleSize, weight: .semibold))
                Spacer()

                Button("Refresh") {
                    model.refreshSkillsSurface()
                }
                .buttonStyle(.bordered)

                Button("Install Skill…") {
                    isInstallSkillSheetVisible = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedProjectID == nil)
            }
            .padding(tokens.spacing.medium)

            if let skillStatusMessage = model.skillStatusMessage {
                Text(skillStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, tokens.spacing.medium)
            }

            skillsSurface
                .padding(tokens.spacing.medium)

            Spacer(minLength: 0)
        }
        .navigationTitle("Skills")
    }

    @ViewBuilder
    private var skillsSurface: some View {
        switch model.skillsState {
        case .idle, .loading:
            LoadingStateView(title: "Scanning installed skills…")
        case let .failed(message):
            ErrorStateView(title: "Couldn’t load skills", message: message, actionLabel: "Retry") {
                model.refreshSkillsSurface()
            }
        case let .loaded(skills) where skills.isEmpty:
            EmptyStateView(
                title: "No skills discovered",
                message: "Install a skill from git or npx, then enable it for this project.",
                systemImage: "square.stack.3d.up"
            )
        case let .loaded(skills):
            List(skills) { item in
                SkillRow(
                    item: item,
                    hasSelectedProject: model.selectedProjectID != nil,
                    onToggle: { enabled in
                        model.setSkillEnabled(item, enabled: enabled)
                    },
                    onInsert: {
                        model.selectSkillForComposer(item)
                        model.navigationSection = .chats
                    },
                    onUpdate: {
                        model.updateSkill(item)
                    }
                )
            }
            .listStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: tokens.radius.medium))
        }
    }
}
