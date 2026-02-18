import SwiftUI

struct UntrustedShellWarningSheet: View {
    let context: UntrustedShellWarningContext
    let onCancel: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Untrusted Project Shell Access")
                .font(.title3.weight(.semibold))

            Text("Project: \(context.projectName)")
                .font(.subheadline.weight(.semibold))

            Text(
                "Shell panes run local commands directly on your machine and are not restricted by project runtime safety settings. " +
                    "Continue only if you trust this project folder."
            )
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }
}
