import CodexChatCore
import CodexChatUI
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    @State private var generalSandboxMode: ProjectSandboxMode = .readOnly
    @State private var generalApprovalPolicy: ProjectApprovalPolicy = .untrusted
    @State private var generalNetworkAccess = false
    @State private var generalWebSearchMode: ProjectWebSearchMode = .cached
    @State private var generalMemoryWriteMode: ProjectMemoryWriteMode = .off
    @State private var generalMemoryEmbeddingsEnabled = false
    @State private var isSyncingGeneralProject = false
    @State private var pendingGeneralSafetySettings: ProjectSafetySettings?
    @State private var isGeneralDangerConfirmationVisible = false
    @State private var generalDangerConfirmationInput = ""
    @State private var generalDangerConfirmationError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                accountCard
                CodexConfigSettingsSection(model: model)
                generalProjectCard
                diagnosticsCard
                storageCard
            }
            .padding(.horizontal, SkillsModsTheme.pageHorizontalInset)
            .padding(.vertical, SkillsModsTheme.pageVerticalInset)
        }
        .background(SkillsModsTheme.canvasBackground(tokens: tokens))
        .onAppear {
            syncGeneralProjectFromModel()
        }
        .onReceive(model.$projectsState) { _ in
            syncGeneralProjectFromModel()
        }
        .sheet(isPresented: $isGeneralDangerConfirmationVisible) {
            AppDangerConfirmationSheet(
                phrase: model.dangerConfirmationPhrase,
                input: $generalDangerConfirmationInput,
                errorText: generalDangerConfirmationError,
                onCancel: {
                    generalDangerConfirmationInput = ""
                    generalDangerConfirmationError = nil
                    pendingGeneralSafetySettings = nil
                    isGeneralDangerConfirmationVisible = false
                },
                onConfirm: {
                    guard generalDangerConfirmationInput.trimmingCharacters(in: .whitespacesAndNewlines) == model.dangerConfirmationPhrase else {
                        generalDangerConfirmationError = "Phrase did not match."
                        return
                    }
                    if let pendingGeneralSafetySettings {
                        model.updateGeneralProjectSafetySettings(
                            sandboxMode: pendingGeneralSafetySettings.sandboxMode,
                            approvalPolicy: pendingGeneralSafetySettings.approvalPolicy,
                            networkAccess: pendingGeneralSafetySettings.networkAccess,
                            webSearch: pendingGeneralSafetySettings.webSearch
                        )
                    }
                    generalDangerConfirmationInput = ""
                    generalDangerConfirmationError = nil
                    pendingGeneralSafetySettings = nil
                    isGeneralDangerConfirmationVisible = false
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 46, weight: .semibold, design: .rounded))

            Text("Global CodexChat configuration and General project controls.")
                .font(.title3)
                .foregroundStyle(SkillsModsTheme.mutedText(tokens: tokens))
        }
    }

    private var accountCard: some View {
        SkillsModsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Account")
                    .font(.title3.weight(.semibold))

                LabeledContent("Current") {
                    Text(model.accountSummaryText)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Auth mode") {
                    Text(model.accountState.authMode.rawValue)
                        .foregroundStyle(.secondary)
                }

                if let message = model.accountStatusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        model.signInWithChatGPT()
                    } label: {
                        Label("Sign in with ChatGPT", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(model.isAccountOperationInProgress)

                    Button {
                        model.presentAPIKeyPrompt()
                    } label: {
                        Label("Use API Key…", systemImage: "key")
                    }
                    .disabled(model.isAccountOperationInProgress)

                    Button {
                        model.launchDeviceCodeLogin()
                    } label: {
                        Label("Device-Code Login", systemImage: "qrcode")
                    }
                    .disabled(model.isAccountOperationInProgress)

                    Button(role: .destructive) {
                        model.logoutAccount()
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(model.isAccountOperationInProgress)
                }

                Text("API keys are stored in macOS Keychain. Per-project secret references are tracked in local metadata.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generalProjectCard: some View {
        SkillsModsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("General Project")
                    .font(.title3.weight(.semibold))

                if let generalProject = model.generalProject {
                    LabeledContent("Name") {
                        Text(generalProject.name)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Path") {
                        Text(generalProject.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 8) {
                        Button("Trust") {
                            model.trustGeneralProject()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(generalProject.trustState == .trusted)

                        Button("Mark Untrusted") {
                            model.untrustGeneralProject()
                        }
                        .buttonStyle(.bordered)
                        .disabled(generalProject.trustState == .untrusted)
                    }

                    Divider()

                    Text("Safety")
                        .font(.headline)

                    Picker("Sandbox mode", selection: $generalSandboxMode) {
                        Text("Read-only").tag(ProjectSandboxMode.readOnly)
                        Text("Workspace-write").tag(ProjectSandboxMode.workspaceWrite)
                        Text("Danger full access").tag(ProjectSandboxMode.dangerFullAccess)
                    }
                    .pickerStyle(.menu)

                    Picker("Approval policy", selection: $generalApprovalPolicy) {
                        Text("Untrusted").tag(ProjectApprovalPolicy.untrusted)
                        Text("On request").tag(ProjectApprovalPolicy.onRequest)
                        Text("Never").tag(ProjectApprovalPolicy.never)
                    }
                    .pickerStyle(.menu)

                    Toggle("Allow network access in workspace-write", isOn: $generalNetworkAccess)
                        .disabled(generalSandboxMode != .workspaceWrite)
                        .onChange(of: generalSandboxMode) { _, newValue in
                            if newValue != .workspaceWrite {
                                generalNetworkAccess = false
                            }
                        }

                    Picker("Web search mode", selection: $generalWebSearchMode) {
                        Text("Cached").tag(ProjectWebSearchMode.cached)
                        Text("Live").tag(ProjectWebSearchMode.live)
                        Text("Disabled").tag(ProjectWebSearchMode.disabled)
                    }
                    .pickerStyle(.menu)

                    Button("Save General Safety Settings") {
                        let settings = ProjectSafetySettings(
                            sandboxMode: generalSandboxMode,
                            approvalPolicy: generalApprovalPolicy,
                            networkAccess: generalNetworkAccess,
                            webSearch: generalWebSearchMode
                        )

                        if model.requiresDangerConfirmation(
                            sandboxMode: settings.sandboxMode,
                            approvalPolicy: settings.approvalPolicy
                        ) {
                            pendingGeneralSafetySettings = settings
                            generalDangerConfirmationInput = ""
                            generalDangerConfirmationError = nil
                            isGeneralDangerConfirmationVisible = true
                        } else {
                            model.updateGeneralProjectSafetySettings(
                                sandboxMode: settings.sandboxMode,
                                approvalPolicy: settings.approvalPolicy,
                                networkAccess: settings.networkAccess,
                                webSearch: settings.webSearch
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Divider()

                    Text("Memory")
                        .font(.headline)

                    Picker("After each completed turn", selection: $generalMemoryWriteMode) {
                        Text("Off").tag(ProjectMemoryWriteMode.off)
                        Text("Summaries only").tag(ProjectMemoryWriteMode.summariesOnly)
                        Text("Summaries + key facts").tag(ProjectMemoryWriteMode.summariesAndKeyFacts)
                    }
                    .pickerStyle(.menu)
                    .disabled(isSyncingGeneralProject)

                    Toggle("Enable semantic retrieval (advanced)", isOn: $generalMemoryEmbeddingsEnabled)
                        .disabled(isSyncingGeneralProject)

                    Button("Save General Memory Settings") {
                        model.updateGeneralProjectMemorySettings(
                            writeMode: generalMemoryWriteMode,
                            embeddingsEnabled: generalMemoryEmbeddingsEnabled
                        )
                    }
                    .buttonStyle(.borderedProminent)

                    Text("General project memory is stored under the General project folder in `memory/*.md`.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("General project is unavailable.")
                        .foregroundStyle(.secondary)
                }

                if let status = model.projectStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let memoryStatus = model.memoryStatusMessage {
                    Text(memoryStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var diagnosticsCard: some View {
        SkillsModsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Diagnostics")
                    .font(.title3.weight(.semibold))

                Button {
                    model.copyDiagnosticsBundle()
                } label: {
                    Label("Copy diagnostics bundle", systemImage: "doc.zipper")
                }
                .disabled(model.isAccountOperationInProgress)

                Text("Exports non-sensitive runtime state and logs as a zip archive, then copies the saved file path to clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var storageCard: some View {
        SkillsModsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Storage")
                    .font(.title3.weight(.semibold))

                LabeledContent("Root") {
                    Text(model.storageRootPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    Button {
                        model.changeStorageRoot()
                    } label: {
                        Label("Change Root…", systemImage: "folder.badge.gearshape")
                    }

                    Button {
                        model.revealStorageRoot()
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }

                Text("Changing the storage root moves CodexChat-managed data and requires an app restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let storageStatusMessage = model.storageStatusMessage {
                    Text(storageStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func syncGeneralProjectFromModel() {
        guard let project = model.generalProject else { return }
        isSyncingGeneralProject = true
        generalSandboxMode = project.sandboxMode
        generalApprovalPolicy = project.approvalPolicy
        generalNetworkAccess = project.networkAccess
        generalWebSearchMode = project.webSearch
        generalMemoryWriteMode = project.memoryWriteMode
        generalMemoryEmbeddingsEnabled = project.memoryEmbeddingsEnabled
        isSyncingGeneralProject = false
    }
}

private struct AppDangerConfirmationSheet: View {
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

            Text("Type the confirmation phrase to enable dangerous General project settings.")
                .foregroundStyle(.secondary)

            Text(phrase)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .tokenCard(style: .card, radius: 8, strokeOpacity: 0.06)

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
