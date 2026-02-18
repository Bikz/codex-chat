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

                HStack {
                    Button("Sign in with ChatGPT") {
                        model.signInWithChatGPT()
                    }
                    .disabled(model.isAccountOperationInProgress)

                    Button("Use API Key…") {
                        model.presentAPIKeyPrompt()
                    }
                    .disabled(model.isAccountOperationInProgress)

                    Button("Logout") {
                        model.logoutAccount()
                    }
                    .disabled(model.isAccountOperationInProgress)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Button("Use Device-Code Login") {
                        model.launchDeviceCodeLogin()
                    }
                    .disabled(model.isAccountOperationInProgress)

                    Text("Device-code availability can depend on workspace policy settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("API keys are stored in macOS Keychain. Per-project secret references are tracked in local metadata.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                Button("Copy diagnostics bundle") {
                    model.copyDiagnosticsBundle()
                }
                .disabled(model.isAccountOperationInProgress)

                Text("Exports non-sensitive runtime state and logs as a zip archive, then copies the saved file path to clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(minWidth: 620, minHeight: 440)
    }
}
