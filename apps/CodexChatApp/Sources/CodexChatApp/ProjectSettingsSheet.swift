import CodexChatCore
import CodexChatUI
import SwiftUI

struct ProjectSettingsSafetyDraft: Equatable {
    var sandboxMode: ProjectSandboxMode
    var approvalPolicy: ProjectApprovalPolicy
    var networkAccess: Bool
    var webSearchMode: ProjectWebSearchMode
}

struct ProjectSettingsSheet: View {
    static let minimumWindowSize = CGSize(width: 760, height: 620)
    static let detailMaxContentWidth: CGFloat = 980

    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    @State private var sandboxMode: ProjectSandboxMode = .readOnly
    @State private var approvalPolicy: ProjectApprovalPolicy = .untrusted
    @State private var networkAccess = false
    @State private var webSearchMode: ProjectWebSearchMode = .cached
    @State private var memoryWriteMode: ProjectMemoryWriteMode = .off
    @State private var memoryEmbeddingsEnabled = false
    @State private var confirmationInput = ""
    @State private var confirmationError: String?
    @State private var isDangerConfirmationVisible = false
    @State private var isRemoveProjectConfirmationVisible = false
    @State private var pendingSafetySettings: ProjectSafetySettings?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: tokens.spacing.medium) {
                SettingsHeroHeader(
                    eyebrow: "Settings",
                    title: projectHeaderTitle,
                    subtitle: projectHeaderSubtitle,
                    symbolName: projectHeaderSymbol
                ) {
                    Button {
                        model.closeProjectSettings()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close Project Settings")
                }

                if let project = model.selectedProject {
                    projectSummaryCard(project)
                    trustAndSafetyCard(project)
                    memoryCard
                    if !project.isGeneralProject {
                        projectDisconnectCard(project)
                    }
                    archivedChatsCard
                } else {
                    SettingsSectionCard(
                        title: "Project Settings",
                        subtitle: "Select a project first."
                    ) {
                        Text("No project selected.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let status = model.projectStatusMessage {
                    statusBanner(status)
                }
            }
            .frame(maxWidth: Self.detailMaxContentWidth, alignment: .leading)
            .padding(tokens.spacing.medium)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationTitle("")
        .tint(Color(hex: tokens.palette.accentHex))
        .background(
            settingsDetailBackground
                .ignoresSafeArea(.container, edges: SettingsLiquidGlassStyle.safeAreaExtensionEdges)
        )
        .frame(
            minWidth: Self.minimumWindowSize.width,
            minHeight: Self.minimumWindowSize.height
        )
        .animation(.easeInOut(duration: tokens.motion.transitionDuration), value: model.selectedProject?.id)
        .onAppear {
            syncStateFromSelectedProject()
            Task {
                try? await model.refreshArchivedThreads()
            }
        }
        .onChange(of: model.selectedProject?.id) { _, _ in
            syncStateFromSelectedProject()
            Task {
                try? await model.refreshArchivedThreads()
            }
        }
        .sheet(isPresented: $isDangerConfirmationVisible) {
            DangerConfirmationSheet(
                phrase: model.dangerConfirmationPhrase,
                subtitle: "Type the confirmation phrase to enable dangerous project settings.",
                input: $confirmationInput,
                errorText: confirmationError,
                onCancel: {
                    confirmationInput = ""
                    confirmationError = nil
                    pendingSafetySettings = nil
                    isDangerConfirmationVisible = false
                },
                onConfirm: {
                    guard DangerConfirmationSheet.isPhraseMatch(
                        input: confirmationInput,
                        phrase: model.dangerConfirmationPhrase
                    ) else {
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
        .alert("Remove project from CodexChat?", isPresented: $isRemoveProjectConfirmationVisible) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                model.removeSelectedProjectFromCodexChat()
            }
        } message: {
            if let project = model.selectedProject {
                Text("\"\(project.name)\" will be disconnected from CodexChat. Project files stay on disk.")
            } else {
                Text("This project will be disconnected from CodexChat. Project files stay on disk.")
            }
        }
    }

    private var projectHeaderTitle: String {
        model.selectedProject?.name ?? "Project Settings"
    }

    private var projectHeaderSubtitle: String {
        if model.selectedProject?.isGeneralProject == true {
            return "General project trust, safety, memory, and archived chat controls."
        }
        return "Project-specific trust, safety, memory, and archived chat controls."
    }

    private var projectHeaderSymbol: String {
        if model.selectedProject?.isGeneralProject == true {
            return "globe.americas.fill"
        }
        return "folder.badge.gearshape"
    }

    private var settingsDetailBackground: some View {
        let isCustomThemeEnabled = model.userThemeCustomization.isEnabled
        return themedBackground(
            baseHex: isCustomThemeEnabled
                ? (model.userThemeCustomization.backgroundHex ?? tokens.palette.backgroundHex)
                : tokens.palette.backgroundHex,
            gradientHex: isCustomThemeEnabled ? model.userThemeCustomization.chatGradientHex : nil
        )
    }

    private func projectSummaryCard(_ project: ProjectRecord) -> some View {
        SettingsSectionCard(
            title: "Project",
            subtitle: "Identity and trust posture for the selected project."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsFieldRow(label: "Name") {
                    Text(project.name)
                }

                SettingsFieldRow(label: "Path") {
                    Text(project.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                SettingsFieldRow(label: "Trust") {
                    SettingsStatusBadge(
                        project.trustState == .trusted ? "Trusted" : "Untrusted",
                        tone: project.trustState == .trusted ? .accent : .neutral
                    )
                }

                let isGitInitialized = AppModel.isGitProject(path: project.path)
                SettingsFieldRow(label: "Git") {
                    SettingsStatusBadge(
                        isGitInitialized ? "Initialized" : "Not initialized",
                        tone: isGitInitialized ? .accent : .neutral
                    )
                }

                if !isGitInitialized {
                    Button("Initialize Git Repository") {
                        model.initializeGitForSelectedProject()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func trustAndSafetyCard(_ project: ProjectRecord) -> some View {
        SettingsSectionCard(
            title: "Trust & Safety",
            subtitle: "Controls for sandboxing, approvals, network access, and web search."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button("Trust") {
                        model.trustSelectedProject()
                    }
                    .buttonStyle(.bordered)
                    .disabled(project.trustState == .trusted)
                    .accessibilityHint("Marks this project as trusted.")

                    Button("Mark Untrusted", role: .destructive) {
                        model.untrustSelectedProject()
                    }
                    .buttonStyle(.bordered)
                    .disabled(project.trustState == .untrusted)
                    .accessibilityHint("Marks this project as untrusted.")
                }

                Picker("Sandbox mode", selection: $sandboxMode) {
                    ForEach(ProjectSandboxMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Picker("Approval policy", selection: $approvalPolicy) {
                    ForEach(ProjectApprovalPolicy.allCases, id: \.self) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Allow network access in workspace-write", isOn: $networkAccess)
                    .disabled(sandboxMode != .workspaceWrite)
                    .onChange(of: sandboxMode) { _, newValue in
                        networkAccess = Self.clampedNetworkAccess(for: newValue, networkAccess: networkAccess)
                    }
                    .accessibilityHint("Only available when sandbox mode is workspace-write.")

                Picker("Web search mode", selection: $webSearchMode) {
                    ForEach(ProjectWebSearchMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Text("Use read-only + untrusted for unknown projects. Danger full access or never-approve mode requires explicit confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Open Local Safety Docs") {
                        model.openSafetyPolicyDocument()
                    }
                    .buttonStyle(.bordered)

                    Button("Save Safety Settings") {
                        saveSafetySettings()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Saves updated safety settings for this project.")
                }
            }
        }
    }

    private var memoryCard: some View {
        SettingsSectionCard(
            title: "Memory",
            subtitle: "Memory write and retrieval behavior for this project."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("After each completed turn", selection: $memoryWriteMode) {
                    Text("Off").tag(ProjectMemoryWriteMode.off)
                    Text("Summaries only").tag(ProjectMemoryWriteMode.summariesOnly)
                    Text("Summaries + key facts").tag(ProjectMemoryWriteMode.summariesAndKeyFacts)
                }
                .pickerStyle(.menu)

                Toggle("Enable semantic retrieval (advanced)", isOn: $memoryEmbeddingsEnabled)

                Button("Save Memory Settings") {
                    model.updateSelectedProjectMemorySettings(
                        writeMode: memoryWriteMode,
                        embeddingsEnabled: memoryEmbeddingsEnabled
                    )
                }
                .buttonStyle(.bordered)

                Text("Project memory is stored under this project's `memory/*.md` files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let memoryStatus = model.memoryStatusMessage {
                    Text(memoryStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func projectDisconnectCard(_ project: ProjectRecord) -> some View {
        SettingsSectionCard(
            title: "Project Membership",
            subtitle: "Disconnect this project from CodexChat without deleting files.",
            emphasis: .secondary
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Removes project metadata, chats, and per-project settings from this app. Files in \"\(project.path)\" remain untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    isRemoveProjectConfirmationVisible = true
                } label: {
                    Label("Remove Project from CodexChat", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Disconnects this project from CodexChat while keeping files on disk.")
            }
        }
    }

    private var archivedChatsCard: some View {
        SettingsSectionCard(
            title: "Archived Chats",
            subtitle: "Manage archived conversation threads for this project.",
            emphasis: .secondary
        ) {
            archivedChatsSection
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

    private func syncStateFromSelectedProject() {
        guard let project = model.selectedProject else { return }
        let draft = Self.safetyDraft(from: project)
        sandboxMode = draft.sandboxMode
        approvalPolicy = draft.approvalPolicy
        networkAccess = draft.networkAccess
        webSearchMode = draft.webSearchMode
        memoryWriteMode = project.memoryWriteMode
        memoryEmbeddingsEnabled = project.memoryEmbeddingsEnabled
    }

    static func safetyDraft(from project: ProjectRecord) -> ProjectSettingsSafetyDraft {
        ProjectSettingsSafetyDraft(
            sandboxMode: project.sandboxMode,
            approvalPolicy: project.approvalPolicy,
            networkAccess: project.networkAccess,
            webSearchMode: project.webSearch
        )
    }

    static func clampedNetworkAccess(for sandboxMode: ProjectSandboxMode, networkAccess: Bool) -> Bool {
        guard sandboxMode == .workspaceWrite else {
            return false
        }
        return networkAccess
    }

    @ViewBuilder
    private var archivedChatsSection: some View {
        if let selectedProjectID = model.selectedProject?.id {
            switch model.archivedThreadsState {
            case .idle, .loading:
                LoadingStateView(title: "Loading archived chats…")
                    .frame(maxHeight: 120)
            case let .failed(message):
                ErrorStateView(title: "Archived chats unavailable", message: message, actionLabel: "Retry") {
                    Task {
                        try? await model.refreshArchivedThreads()
                    }
                }
                .frame(maxHeight: 160)
            case let .loaded(allArchivedThreads):
                let threads = allArchivedThreads.filter { $0.projectId == selectedProjectID }
                if threads.isEmpty {
                    Text("No archived chats for this project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(threads) { thread in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(thread.title)
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(compactRelativeAge(from: thread.archivedAt ?? thread.updatedAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Button("Unarchive") {
                                        model.unarchiveThread(threadID: thread.id)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(8)
                                .tokenCard(style: .panel, radius: tokens.radius.small, strokeOpacity: 0.08)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
        } else {
            Text("Select a project to view archived chats.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func compactRelativeAge(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        let minute = 60
        let hour = minute * 60
        let day = hour * 24
        let week = day * 7

        if seconds < minute {
            return "now"
        }
        if seconds < hour {
            return "\(seconds / minute)m"
        }
        if seconds < day {
            return "\(seconds / hour)h"
        }
        if seconds < week {
            return "\(seconds / day)d"
        }
        return "\(seconds / week)w"
    }

    private func statusBanner(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .tokenCard(
                style: .panel,
                radius: tokens.radius.medium,
                strokeOpacity: 0.08
            )
    }

    @ViewBuilder
    private func themedBackground(baseHex: String, gradientHex: String?) -> some View {
        if model.userThemeCustomization.isEnabled {
            ZStack {
                Color(hex: baseHex)
                    .opacity(model.isTransparentThemeMode ? 0.58 : 1)
                if let gradientHex, model.userThemeCustomization.gradientStrength > 0 {
                    LinearGradient(
                        colors: [Color(hex: baseHex), Color(hex: gradientHex)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(model.userThemeCustomization.gradientStrength)
                }
            }
        } else {
            Color(hex: baseHex)
        }
    }
}
