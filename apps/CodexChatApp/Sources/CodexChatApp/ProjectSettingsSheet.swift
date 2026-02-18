import CodexChatCore
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
