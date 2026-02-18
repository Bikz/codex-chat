import CodexChatUI
import SwiftUI

struct DangerConfirmationSheet: View {
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
