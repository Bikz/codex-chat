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
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    @State private var sandboxMode: ProjectSandboxMode = .readOnly
    @State private var approvalPolicy: ProjectApprovalPolicy = .untrusted
    @State private var networkAccess = false
    @State private var webSearchMode: ProjectWebSearchMode = .cached
    @State private var confirmationInput = ""
    @State private var confirmationError: String?
    @State private var isDangerConfirmationVisible = false
    @State private var pendingSafetySettings: ProjectSafetySettings?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsInlineHeader(
                    eyebrow: "Settings",
                    title: "Project Settings",
                    subtitle: "Per-project trust, safety, and archived chat controls."
                )

                if let project = model.selectedProject {
                    projectSummaryCard(project)
                    trustAndSafetyCard(project)
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
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationTitle("")
        .tint(Color(hex: tokens.palette.accentHex))
        .background(Color(hex: tokens.palette.backgroundHex))
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            syncSafetyStateFromSelectedProject()
            Task {
                try? await model.refreshArchivedThreads()
            }
        }
        .onChange(of: model.selectedProject?.id) { _, _ in
            syncSafetyStateFromSelectedProject()
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
    }

    private func projectSummaryCard(_ project: ProjectRecord) -> some View {
        SettingsSectionCard(
            title: "Project Summary",
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
            subtitle: "Runtime guardrails and approval policy for this project."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button("Trust Project") {
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
                    .onChange(of: sandboxMode) { _, newValue in
                        networkAccess = Self.clampedNetworkAccess(for: newValue, networkAccess: networkAccess)
                    }
                    .accessibilityHint("Only available when sandbox mode is workspace-write.")

                Picker("Web search mode", selection: $webSearchMode) {
                    Text("Cached").tag(ProjectWebSearchMode.cached)
                    Text("Live").tag(ProjectWebSearchMode.live)
                    Text("Disabled").tag(ProjectWebSearchMode.disabled)
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

    private var archivedChatsCard: some View {
        SettingsSectionCard(
            title: "Archived Chats",
            subtitle: "Manage archived conversation threads.",
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

    private func syncSafetyStateFromSelectedProject() {
        guard let project = model.selectedProject else { return }
        let draft = Self.safetyDraft(from: project)
        sandboxMode = draft.sandboxMode
        approvalPolicy = draft.approvalPolicy
        networkAccess = draft.networkAccess
        webSearchMode = draft.webSearchMode
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
        case let .loaded(threads) where threads.isEmpty:
            Text("No archived chats yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .loaded(threads):
            let projectNamesByID = Dictionary(uniqueKeysWithValues: model.projects.map { ($0.id, $0.name) })
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(threads) { thread in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(thread.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(projectName(for: thread.projectId, projectNamesByID: projectNamesByID))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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

    private func projectName(for projectID: UUID, projectNamesByID: [UUID: String]) -> String {
        projectNamesByID[projectID] ?? "Unknown project"
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
}
