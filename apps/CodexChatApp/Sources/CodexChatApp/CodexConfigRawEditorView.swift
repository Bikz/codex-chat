import SwiftUI

struct CodexConfigRawEditorView: View {
    @Binding var rawText: String
    let parseError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("config.toml")
                .font(.headline)

            TextEditor(text: $rawText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 320)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            if let parseError {
                Text(parseError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Raw editor parses TOML live. Save is disabled until parse errors are resolved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
