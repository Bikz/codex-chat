import CodexChatCore
import CodexChatUI
import SwiftUI

struct ProjectSettingsSheet: View {
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

                LabeledContent("Git") {
                    Text(AppModel.isGitProject(path: project.path) ? "Initialized" : "Not initialized")
                        .foregroundStyle(AppModel.isGitProject(path: project.path) ? .green : .secondary)
                }

                if !AppModel.isGitProject(path: project.path) {
                    Button("Initialize Git Repository") {
                        model.initializeGitForSelectedProject()
                    }
                    .buttonStyle(.bordered)
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
                    .onChange(of: sandboxMode) { _, newValue in
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

            Divider()

            Text("Archived Chats")
                .font(.headline)

            archivedChatsSection

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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(threads) { thread in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(thread.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(projectName(for: thread.projectId))
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
                        .tokenCard(style: .card, radius: 8, strokeOpacity: 0.06)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func projectName(for projectID: UUID) -> String {
        model.projects.first(where: { $0.id == projectID })?.name ?? "Unknown project"
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
