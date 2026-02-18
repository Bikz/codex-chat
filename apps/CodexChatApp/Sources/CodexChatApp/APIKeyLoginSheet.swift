import SwiftUI

struct APIKeyLoginSheet: View {
    @ObservedObject var model: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use API Key")
                .font(.title3.weight(.semibold))

            Text("Your key will be sent to Codex app-server for login and stored in macOS Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)

            SecureField("sk-...", text: $model.pendingAPIKey)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)

            HStack {
                Spacer()
                Button("Cancel") {
                    model.cancelAPIKeyPrompt()
                }
                Button("Sign in") {
                    model.submitAPIKeyLogin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .onAppear {
            isFocused = true
        }
    }
}
