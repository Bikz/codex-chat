import CodexKit
import SwiftUI

struct ApprovalRequestSheet: View {
    @ObservedObject var model: AppModel
    let request: RuntimeApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Approval Required")
                .font(.title3.weight(.semibold))

            if let warning = model.approvalDangerWarning(for: request) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.callout)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            LabeledContent("Type") {
                Text(request.kind.rawValue)
                    .foregroundStyle(.secondary)
            }

            if let reason = request.reason, !reason.isEmpty {
                LabeledContent("Reason") {
                    Text(reason)
                        .foregroundStyle(.secondary)
                }
            }

            if let cwd = request.cwd, !cwd.isEmpty {
                LabeledContent("Working dir") {
                    Text(cwd)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if !request.command.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Command")
                        .font(.subheadline.weight(.semibold))
                    Text(request.command.joined(separator: " "))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if !request.changes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("File changes")
                        .font(.subheadline.weight(.semibold))
                    ForEach(request.changes, id: \.path) { change in
                        Text("\(change.kind): \(change.path)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let status = model.approvalStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Decline") {
                    model.declinePendingApproval()
                }
                .buttonStyle(.bordered)

                Button("Approve Once") {
                    model.approvePendingApprovalOnce()
                }
                .buttonStyle(.borderedProminent)

                Button("Approve for Session") {
                    model.approvePendingApprovalForSession()
                }
                .buttonStyle(.bordered)
            }
            .disabled(model.isApprovalDecisionInProgress)
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 360)
    }
}
