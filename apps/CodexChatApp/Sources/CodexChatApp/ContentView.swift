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
                    HStack(spacing: tokens.spacing.small) {
                        TextField(composerPlaceholder, text: $model.composerText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1 ... 4)

                        Button("Send") {
                            model.sendMessage()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: tokens.palette.accentHex))
                        .disabled(!model.canSendMessages)

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
                            Label("Skill", systemImage: "wand.and.stars")
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(model.enabledSkillsForSelectedProject.isEmpty)

                        Button {
                            isInsertMemorySheetVisible = true
                        } label: {
                            Label("Insert memory snippet", systemImage: "brain")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .help("Insert memory snippet")
                        .disabled(model.selectedProjectID == nil)

                        Button("Reveal Chat File") {
                            model.revealSelectedThreadArchiveInFinder()
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.selectedThreadID == nil)

                        Button("Review Changes") {
                            model.openReviewChanges()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canReviewChanges)

                        Button(model.isLogsDrawerVisible ? "Hide Logs" : "Terminal / Logs") {
                            model.toggleLogsDrawer()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let selectedSkill = model.selectedSkillForComposer {
                        HStack {
                            Label("Using \(selectedSkill.skill.name)", systemImage: "checkmark.seal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Clear") {
                                model.clearSelectedSkillForComposer()
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }
                    }
                }
                .padding(tokens.spacing.medium)
                .background(Color(hex: tokens.palette.panelHex).opacity(0.5))

                if model.isLogsDrawerVisible {
                    Divider()
                    ThreadLogsDrawer(entries: model.selectedThreadLogs)
                        .frame(height: 180)
                        .background(Color(hex: tokens.palette.panelHex).opacity(0.82))
                }
            }
        }
        .navigationTitle("Conversation")
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
                List(entries) { entry in
                    switch entry {
                    case let .message(message):
                        MessageRow(message: message, tokens: tokens)
                            .padding(.vertical, tokens.spacing.xSmall)
                            .listRowSeparator(.hidden)
                    case let .actionCard(card):
                        ActionCardRow(card: card)
                            .padding(.vertical, tokens.spacing.xSmall)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
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

private struct MessageRow: View {
    let message: ChatMessage
    let tokens: DesignTokens

    var body: some View {
        let bubbleHex = message.role == .user ? tokens.bubbles.userBackgroundHex : tokens.bubbles.assistantBackgroundHex
        let isPlain = tokens.bubbles.style == .plain
        let foreground: Color = {
            if message.role == .user, !isPlain {
                return .white
            }
            return .primary
        }()

        VStack(alignment: .leading, spacing: tokens.spacing.xSmall) {
            Text(message.role.rawValue.capitalized)
                .font(.system(size: tokens.typography.captionSize, weight: .medium))
                .foregroundStyle(isPlain ? .secondary : foreground.opacity(0.9))
            Text(message.text)
                .font(.system(size: tokens.typography.bodySize))
                .foregroundStyle(foreground)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(bubbleBackground(style: tokens.bubbles.style, colorHex: bubbleHex, tokens: tokens))
    }

    @ViewBuilder
    private func bubbleBackground(style: DesignTokens.BubbleStyle, colorHex: String, tokens: DesignTokens) -> some View {
        let shape = RoundedRectangle(cornerRadius: tokens.radius.medium)
        switch style {
        case .plain:
            shape.fill(Color.clear)
        case .glass:
            shape.fill(tokens.materials.cardMaterial.material)
                .overlay(shape.fill(Color(hex: colorHex).opacity(0.12)))
        case .solid:
            shape.fill(Color(hex: colorHex))
        }
    }
}

private struct ActionCardRow: View {
    let card: ActionCard
    @State private var isExpanded = false
    @Environment(\.designTokens) private var tokens

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
        .background(tokens.materials.cardMaterial.material, in: RoundedRectangle(cornerRadius: tokens.radius.medium))
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
    @State private var sandboxMode: ProjectSandboxMode = .readOnly
    @State private var approvalPolicy: ProjectApprovalPolicy = .untrusted
    @State private var networkAccess = false
    @State private var webSearchMode: ProjectWebSearchMode = .cached
    @State private var confirmationInput = ""
    @State private var confirmationError: String?
    @State private var isDangerConfirmationVisible = false
    @State private var pendingSafetySettings: ProjectSafetySettings?

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

                Divider()

                Text("Safety Controls")
                    .font(.headline)

                Picker("Sandbox mode", selection: $sandboxMode) {
                    Text("Read-only").tag(ProjectSandboxMode.readOnly)
                    Text("Workspace-write").tag(ProjectSandboxMode.workspaceWrite)
                    Text("Danger full access").tag(ProjectSandboxMode.dangerFullAccess)
                }
                .pickerStyle(.menu)

                Picker("Approval policy", selection: $approvalPolicy) {
                    Text("Untrusted").tag(ProjectApprovalPolicy.untrusted)
                    Text("On request").tag(ProjectApprovalPolicy.onRequest)
                    Text("Never").tag(ProjectApprovalPolicy.never)
                }
                .pickerStyle(.menu)

                Toggle("Allow network access in workspace-write", isOn: $networkAccess)
                    .disabled(sandboxMode != .workspaceWrite)
                    .onChange(of: sandboxMode) { newValue in
                        if newValue != .workspaceWrite {
                            networkAccess = false
                        }
                    }

                Picker("Web search mode", selection: $webSearchMode) {
                    Text("Cached").tag(ProjectWebSearchMode.cached)
                    Text("Live").tag(ProjectWebSearchMode.live)
                    Text("Disabled").tag(ProjectWebSearchMode.disabled)
                }
                .pickerStyle(.menu)

                Text("Use read-only + untrusted for unknown projects. Danger full access or never-approve mode requires explicit confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Local Safety Docs") {
                    model.openSafetyPolicyDocument()
                }
                .buttonStyle(.bordered)

                Button("Save Safety Settings") {
                    saveSafetySettings()
                }
                .buttonStyle(.borderedProminent)

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
        .frame(minWidth: 620, minHeight: 420)
        .onAppear {
            syncSafetyStateFromSelectedProject()
        }
        .onChange(of: model.selectedProject?.id) { _ in
            syncSafetyStateFromSelectedProject()
        }
        .sheet(isPresented: $isDangerConfirmationVisible) {
            DangerConfirmationSheet(
                phrase: model.dangerConfirmationPhrase,
                input: $confirmationInput,
                errorText: confirmationError,
                onCancel: {
                    confirmationInput = ""
                    confirmationError = nil
                    pendingSafetySettings = nil
                    isDangerConfirmationVisible = false
                },
                onConfirm: {
                    guard confirmationInput.trimmingCharacters(in: .whitespacesAndNewlines) == model.dangerConfirmationPhrase else {
                        confirmationError = "Phrase did not match."
                        return
                    }
                    if let pendingSafetySettings {
                        applySafetySettings(pendingSafetySettings)
                    }
                    confirmationInput = ""
                    confirmationError = nil
                    pendingSafetySettings = nil
                    isDangerConfirmationVisible = false
                }
            )
        }
    }

    private func saveSafetySettings() {
        let settings = ProjectSafetySettings(
            sandboxMode: sandboxMode,
            approvalPolicy: approvalPolicy,
            networkAccess: networkAccess,
            webSearch: webSearchMode
        )

        if model.requiresDangerConfirmation(
            sandboxMode: settings.sandboxMode,
            approvalPolicy: settings.approvalPolicy
        ) {
            pendingSafetySettings = settings
            confirmationInput = ""
            confirmationError = nil
            isDangerConfirmationVisible = true
            return
        }

        applySafetySettings(settings)
    }

    private func applySafetySettings(_ settings: ProjectSafetySettings) {
        model.updateSelectedProjectSafetySettings(
            sandboxMode: settings.sandboxMode,
            approvalPolicy: settings.approvalPolicy,
            networkAccess: settings.networkAccess,
            webSearch: settings.webSearch
        )
    }

    private func syncSafetyStateFromSelectedProject() {
        guard let project = model.selectedProject else { return }
        sandboxMode = project.sandboxMode
        approvalPolicy = project.approvalPolicy
        networkAccess = project.networkAccess
        webSearchMode = project.webSearch
    }
}

private struct DangerConfirmationSheet: View {
    let phrase: String
    @Binding var input: String
    let errorText: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm Dangerous Settings")
                .font(.title3.weight(.semibold))

            Text("Type the confirmation phrase to enable dangerous project settings.")
                .foregroundStyle(.secondary)

            Text(phrase)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

            TextField("Type phrase exactly", text: $input)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Confirm") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onAppear {
            isFocused = true
        }
    }
}

private struct ApprovalRequestSheet: View {
    @ObservedObject var model: AppModel
    let request: RuntimeApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Approval Required")
                .font(.title3.weight(.semibold))

            if let warning = model.approvalDangerWarning(for: request) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.callout)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            LabeledContent("Type") {
                Text(request.kind.rawValue)
                    .foregroundStyle(.secondary)
            }

            if let reason = request.reason, !reason.isEmpty {
                LabeledContent("Reason") {
                    Text(reason)
                        .foregroundStyle(.secondary)
                }
            }

            if let cwd = request.cwd, !cwd.isEmpty {
                LabeledContent("Working dir") {
                    Text(cwd)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if !request.command.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Command")
                        .font(.subheadline.weight(.semibold))
                    Text(request.command.joined(separator: " "))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if !request.changes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("File changes")
                        .font(.subheadline.weight(.semibold))
                    ForEach(request.changes, id: \.path) { change in
                        Text("\(change.kind): \(change.path)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let status = model.approvalStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Decline") {
                    model.declinePendingApproval()
                }
                .buttonStyle(.bordered)

                Button("Approve Once") {
                    model.approvePendingApprovalOnce()
                }
                .buttonStyle(.borderedProminent)

                Button("Approve for Session") {
                    model.approvePendingApprovalForSession()
                }
                .buttonStyle(.bordered)
            }
            .disabled(model.isApprovalDecisionInProgress)
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 360)
    }
}

private struct ReviewChangesSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Changes")
                .font(.title3.weight(.semibold))

            if model.selectedThreadChanges.isEmpty {
                EmptyStateView(
                    title: "No changes to review",
                    message: "Run a turn that produces file changes, then review here.",
                    systemImage: "doc.text.magnifyingglass"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(model.selectedThreadChanges.enumerated()), id: \.offset) { _, change in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(change.kind): \(change.path)")
                                    .font(.callout.weight(.semibold))

                                if let diff = change.diff, !diff.isEmpty {
                                    Text(diff)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }

            HStack {
                Button("Revert") {
                    model.revertReviewChanges()
                }
                .buttonStyle(.bordered)
                .disabled(model.selectedThreadChanges.isEmpty)

                Button("Accept") {
                    model.acceptReviewChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedThreadChanges.isEmpty)

                Spacer()

                Button("Close") {
                    model.closeReviewChanges()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 480)
    }
}

private struct ThreadLogsDrawer: View {
    let entries: [ThreadLogEntry]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terminal / Logs")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if entries.isEmpty {
                EmptyStateView(
                    title: "No command output yet",
                    message: "Runtime command output for this thread will appear here.",
                    systemImage: "terminal"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.dateFormatter.string(from: entry.timestamp))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(entry.text)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

private struct SkillRow: View {
    let item: AppModel.SkillListItem
    let hasSelectedProject: Bool
    let onToggle: (Bool) -> Void
    let onInsert: () -> Void
    let onUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.skill.name)
                    .font(.headline)
                Spacer()
                Text(item.skill.scope.rawValue.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
            }

            Text(item.skill.description)
                .font(.callout)
                .foregroundStyle(.secondary)

            if item.skill.hasScripts {
                Label("Risk: scripts/ detected", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(item.skill.skillPath)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)

            HStack {
                Toggle("Enabled for project", isOn: Binding(
                    get: { item.isEnabledForProject },
                    set: { onToggle($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!hasSelectedProject)

                Spacer()

                Button("Use in Composer") {
                    onInsert()
                }
                .buttonStyle(.bordered)
                .disabled(!item.isEnabledForProject)

                Button("Update") {
                    onUpdate()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct InstallSkillSheet: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool

    @State private var source = ""
    @State private var scope: SkillInstallScope = .project
    @State private var installer: SkillInstallerKind = .git
    @State private var trustConfirmed = false

    private var isTrustedSource: Bool {
        model.isTrustedSkillSource(source)
    }

    private var canSubmit: Bool {
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (isTrustedSource || trustConfirmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install Skill")
                .font(.title3.weight(.semibold))

            Text("Install from a git source or run the optional npx installer. Project installs go to `.agents/skills`.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("https://github.com/org/skill-repo.git", text: $source)
                .textFieldStyle(.roundedBorder)

            Picker("Scope", selection: $scope) {
                Text("Project").tag(SkillInstallScope.project)
                Text("Global").tag(SkillInstallScope.global)
            }
            .pickerStyle(.segmented)

            Picker("Installer", selection: $installer) {
                Text("Git Clone").tag(SkillInstallerKind.git)
                if model.isNodeSkillInstallerAvailable {
                    Text("npx skills add").tag(SkillInstallerKind.npx)
                }
            }
            .pickerStyle(.segmented)

            if !isTrustedSource {
                Toggle("I trust this source and want to install it anyway.", isOn: $trustConfirmed)
                    .toggleStyle(.switch)
                Text("Unknown source detected. Installing may run unreviewed scripts.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let status = model.skillStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }

                Button("Install") {
                    model.installSkill(
                        source: source,
                        scope: scope,
                        installer: installer
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || model.isSkillOperationInProgress)
            }
        }
        .padding(20)
        .frame(minWidth: 560)
        .onChange(of: source) { _ in
            trustConfirmed = false
        }
    }
}
