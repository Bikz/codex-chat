import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
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
        .formStyle(.grouped)
        .padding(16)
        .frame(minWidth: 620, minHeight: 440)
    }
}
