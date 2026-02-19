import CodexChatUI
import SwiftUI

struct DangerConfirmationSheet: View {
    let phrase: String
    let subtitle: String
    @Binding var input: String
    let errorText: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.designTokens) private var tokens

    init(
        phrase: String,
        subtitle: String = "Type the confirmation phrase to enable dangerous settings.",
        input: Binding<String>,
        errorText: String?,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.phrase = phrase
        self.subtitle = subtitle
        _input = input
        self.errorText = errorText
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionCard(
                title: "Confirm Dangerous Settings",
                subtitle: subtitle
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(phrase)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            tokens.materials.panelMaterial.material,
                            in: RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08))
                        )
                        .textSelection(.enabled)

                    TextField("Type phrase exactly", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)
                        .accessibilityHint("Enter the exact phrase shown above.")

                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(Color(hex: tokens.palette.accentHex))
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Confirm") {
                    onConfirm()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(minWidth: 500)
        .background(Color(hex: tokens.palette.backgroundHex))
        .onAppear {
            isFocused = true
        }
    }

    static func isPhraseMatch(input: String, phrase: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines) == phrase
    }
}
