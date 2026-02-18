import CodexChatCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var runtimeModelDraft = ""
    @State private var safetySandboxMode: ProjectSandboxMode = .readOnly
    @State private var safetyApprovalPolicy: ProjectApprovalPolicy = .untrusted
    @State private var safetyNetworkAccess = false
    @State private var safetyWebSearchMode: ProjectWebSearchMode = .cached
    @State private var pendingSafetyDefaults: ProjectSafetySettings?
    @State private var isSafetyApplyPromptVisible = false

    var body: some View {
        Form {
            accountSection
            runtimeDefaultsSection
            experimentalSection
            safetyDefaultsSection
            diagnosticsSection
            storageSection
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(minWidth: 700, minHeight: 560)
        .onAppear {
            runtimeModelDraft = model.defaultModel
            syncSafetyDefaultsFromModel()
        }
        .onChange(of: model.defaultSafetySettings) { _ in
            syncSafetyDefaultsFromModel()
        }
        .onChange(of: model.defaultModel) { newValue in
            runtimeModelDraft = newValue
        }
        .confirmationDialog(
            "Apply global safety defaults",
            isPresented: $isSafetyApplyPromptVisible,
            titleVisibility: .visible
        ) {
            Button("Apply to New Projects Only") {
                guard let pendingSafetyDefaults else { return }
                model.saveGlobalSafetyDefaults(pendingSafetyDefaults, applyToExistingProjects: false)
            }

            Button("Apply to Existing + New Projects") {
                guard let pendingSafetyDefaults else { return }
                model.saveGlobalSafetyDefaults(pendingSafetyDefaults, applyToExistingProjects: true)
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose whether these defaults should affect only newly created projects or also update existing projects.")
        }
    }

    private var accountSection: some View {
        Section("Account") {
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

            LabeledContent("Sign in") {
                HStack {
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
                }
            }

            LabeledContent("Device login") {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        model.launchDeviceCodeLogin()
                    } label: {
                        Label("Use Device-Code Login", systemImage: "qrcode")
                    }
                    .disabled(model.isAccountOperationInProgress)

                    Text("Device-code availability can depend on workspace policy settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Sign out") {
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

    private var runtimeDefaultsSection: some View {
        Section("Runtime Defaults") {
            LabeledContent("Model") {
                HStack {
                    TextField("Model ID", text: $runtimeModelDraft)
                        .textFieldStyle(.roundedBorder)

                    Menu("Preset") {
                        ForEach(model.modelPresets, id: \.self) { preset in
                            Button(preset) {
                                runtimeModelDraft = preset
                                model.setDefaultModel(preset)
                            }
                        }
                    }

                    Button("Save") {
                        model.setDefaultModel(runtimeModelDraft)
                    }
                    .disabled(runtimeModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .frame(maxWidth: 420)
            }

            Picker(
                "Reasoning",
                selection: Binding(
                    get: { model.defaultReasoning },
                    set: { model.setDefaultReasoning($0) }
                )
            ) {
                ForEach(AppModel.ReasoningLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Picker(
                "Web search",
                selection: Binding(
                    get: { model.defaultWebSearch },
                    set: { model.setDefaultWebSearch($0) }
                )
            ) {
                Text("Cached").tag(ProjectWebSearchMode.cached)
                Text("Live").tag(ProjectWebSearchMode.live)
                Text("Disabled").tag(ProjectWebSearchMode.disabled)
            }
            .pickerStyle(.segmented)

            Text("Composer controls inherit these defaults. Project safety policy still clamps effective web-search behavior at turn time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var experimentalSection: some View {
        Section("Experimental") {
            ForEach(AppModel.ExperimentalFlag.allCases, id: \.self) { flag in
                Toggle(
                    flag.title,
                    isOn: Binding(
                        get: { model.experimentalFlags.contains(flag) },
                        set: { model.setExperimentalFlag(flag, enabled: $0) }
                    )
                )
            }

            Text("Experimental flags are global app settings and apply to all projects.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var safetyDefaultsSection: some View {
        Section("Safety Defaults") {
            Picker("Sandbox mode", selection: $safetySandboxMode) {
                Text("Read-only").tag(ProjectSandboxMode.readOnly)
                Text("Workspace-write").tag(ProjectSandboxMode.workspaceWrite)
                Text("Danger full access").tag(ProjectSandboxMode.dangerFullAccess)
            }
            .pickerStyle(.menu)

            Picker("Approval policy", selection: $safetyApprovalPolicy) {
                Text("Untrusted").tag(ProjectApprovalPolicy.untrusted)
                Text("On request").tag(ProjectApprovalPolicy.onRequest)
                Text("Never").tag(ProjectApprovalPolicy.never)
            }
            .pickerStyle(.menu)

            Toggle("Allow network access in workspace-write", isOn: $safetyNetworkAccess)
                .disabled(safetySandboxMode != .workspaceWrite)
                .onChange(of: safetySandboxMode) { newValue in
                    if newValue != .workspaceWrite {
                        safetyNetworkAccess = false
                    }
                }

            Picker("Web search mode", selection: $safetyWebSearchMode) {
                Text("Cached").tag(ProjectWebSearchMode.cached)
                Text("Live").tag(ProjectWebSearchMode.live)
                Text("Disabled").tag(ProjectWebSearchMode.disabled)
            }
            .pickerStyle(.menu)

            Button("Save Global Safety Defaults…") {
                pendingSafetyDefaults = ProjectSafetySettings(
                    sandboxMode: safetySandboxMode,
                    approvalPolicy: safetyApprovalPolicy,
                    networkAccess: safetyNetworkAccess,
                    webSearch: safetyWebSearchMode
                )
                isSafetyApplyPromptVisible = true
            }
            .buttonStyle(.borderedProminent)

            Text("These defaults initialize new projects. After saving, you can choose whether to bulk-apply them to existing projects.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let runtimeDefaultsStatusMessage = model.runtimeDefaultsStatusMessage {
                Text(runtimeDefaultsStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            Button {
                model.copyDiagnosticsBundle()
            } label: {
                Label("Copy diagnostics bundle", systemImage: "doc.zipper")
            }
            .disabled(model.isAccountOperationInProgress)
            .help("Exports runtime state and logs as a zip, then copies the file path to clipboard")

            Text("Exports non-sensitive runtime state and logs as a zip archive, then copies the saved file path to clipboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var storageSection: some View {
        Section("Storage") {
            LabeledContent("Root") {
                Text(model.storageRootPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
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

    private func syncSafetyDefaultsFromModel() {
        safetySandboxMode = model.defaultSafetySettings.sandboxMode
        safetyApprovalPolicy = model.defaultSafetySettings.approvalPolicy
        safetyNetworkAccess = model.defaultSafetySettings.networkAccess
        safetyWebSearchMode = model.defaultSafetySettings.webSearch
    }
}
