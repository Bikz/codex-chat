import CodexChatUI
import CodexKit
import SwiftUI

struct ApprovalRequestSheet: View {
    @ObservedObject var model: AppModel
    let request: RuntimeApprovalRequest

    var body: some View {
        ApprovalRequestDialogContent(model: model, request: request, isInline: false)
            .padding(18)
            .frame(minWidth: 620, minHeight: 360)
    }
}

struct InlineApprovalRequestView: View {
    @ObservedObject var model: AppModel
    let request: RuntimeApprovalRequest

    @Environment(\.designTokens) private var tokens

    var body: some View {
        ApprovalRequestDialogContent(model: model, request: request, isInline: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(hex: tokens.palette.panelHex).opacity(model.isTransparentThemeMode ? 0.78 : 0.95),
                in: RoundedRectangle(cornerRadius: tokens.radius.large, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.radius.large, style: .continuous)
                    .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity))
            )
    }
}

struct InlineUserApprovalRequestView: View {
    @ObservedObject var model: AppModel
    let request: AppModel.UserApprovalRequest
    @Binding var permissionRecoveryDetailsNotice: AppModel.PermissionRecoveryNotice?

    var body: some View {
        switch request {
        case let .runtimeApproval(runtimeRequest):
            InlineApprovalRequestView(model: model, request: runtimeRequest)
        case let .computerActionPreview(preview):
            InlineComputerActionPreviewApprovalView(model: model, preview: preview)
        case let .permissionRecovery(notice):
            InlinePermissionRecoveryApprovalView(
                model: model,
                notice: notice,
                permissionRecoveryDetailsNotice: $permissionRecoveryDetailsNotice
            )
        }
    }
}

private struct InlineComputerActionPreviewApprovalView: View {
    @ObservedObject var model: AppModel
    let preview: AppModel.PendingComputerActionPreview
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Approval Required")
                .font(.title3.weight(.semibold))

            Text(preview.providerDisplayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            MarkdownMessageView(
                text: preview.artifact.detailsMarkdown,
                allowsExternalContent: false
            )
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxHeight: 180, alignment: .topLeading)

            if let status = model.computerActionStatusMessage,
               !status.isEmpty
            {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Cancel") {
                    model.cancelPendingComputerActionPreview()
                }
                .buttonStyle(.bordered)

                Button(preview.requiresConfirmation ? "Confirm Run" : "Run") {
                    model.confirmPendingComputerActionPreview()
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(model.isComputerActionExecutionInProgress)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(hex: tokens.palette.panelHex).opacity(model.isTransparentThemeMode ? 0.78 : 0.95),
            in: RoundedRectangle(cornerRadius: tokens.radius.large, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: tokens.radius.large, style: .continuous)
                .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity))
        )
    }
}

private struct InlinePermissionRecoveryApprovalView: View {
    @ObservedObject var model: AppModel
    let notice: AppModel.PermissionRecoveryNotice
    @Binding var permissionRecoveryDetailsNotice: AppModel.PermissionRecoveryNotice?
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title)
                        .font(.subheadline.weight(.semibold))
                    Text(notice.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button("Open Settings") {
                    model.openPermissionRecoverySettings(for: notice.target)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Details") {
                    permissionRecoveryDetailsNotice = notice
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Dismiss") {
                    model.dismissPermissionRecoveryNotice()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(hex: tokens.palette.panelHex).opacity(model.isTransparentThemeMode ? 0.78 : 0.95),
            in: RoundedRectangle(cornerRadius: tokens.radius.large, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: tokens.radius.large, style: .continuous)
                .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity))
        )
    }
}

private struct ApprovalRequestDialogContent: View {
    @ObservedObject var model: AppModel
    let request: RuntimeApprovalRequest
    let isInline: Bool

    @Environment(\.designTokens) private var tokens

    private var commandText: String {
        request.command.joined(separator: " ")
    }

    private var decisionInProgress: Bool {
        model.isSelectedThreadApprovalInProgress || model.isApprovalDecisionInProgress
    }

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

            VStack(alignment: .leading, spacing: 6) {
                Text("Reason")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(primaryReasonText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 14) {
                labeledMeta("Type", request.kind.rawValue)
                if let cwd = request.cwd, !cwd.isEmpty {
                    labeledMeta("Working dir", cwd, monospaced: true)
                }
            }

            if !commandText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Command")
                        .font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal) {
                        Text(commandText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tokenCard(style: .panel, radius: 8, strokeOpacity: 0.06)
                }
            }

            if !request.changes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("File changes")
                        .font(.subheadline.weight(.semibold))
                    ForEach(request.changes.prefix(6), id: \.path) { change in
                        Text("\(change.kind): \(change.path)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if request.changes.count > 6 {
                        Text("+\(request.changes.count - 6) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let status = model.approvalStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
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
            .disabled(decisionInProgress)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(isInline ? 0 : 4)
        .accessibilityElement(children: .contain)
    }

    private var primaryReasonText: String {
        if let reason = request.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            return reason
        }
        let detail = request.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "Codex requested permission before continuing." : detail
    }

    private func labeledMeta(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
