import AppKit
import CodexChatRemoteControl
import SwiftUI

struct RemoteControlSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.medium) {
            header

            if let session = model.remoteControlStatus.session {
                activeSessionView(session: session)
            } else {
                inactiveSessionView
            }

            Toggle("Allow approvals from remote", isOn: $model.allowRemoteApprovals)
                .disabled(true)
                .help("Phase 2: approval actions stay local-only in this release.")

            if let message = model.remoteControlStatusMessage,
               !message.isEmpty
            {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(tokens.spacing.large)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            Task {
                await model.refreshRemoteControlStatus()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.small) {
            Text("Remote Control")
                .font(.title2.weight(.semibold))

            Text("Scan the QR code from your phone to securely control this local Codex Chat session.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Commands execute on this Mac. Never share the join link with anyone you do not trust.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func activeSessionView(session: RemoteControlSessionDescriptor) -> some View {
        VStack(alignment: .leading, spacing: tokens.spacing.medium) {
            HStack(alignment: .top, spacing: tokens.spacing.medium) {
                qrCodeCard(url: session.joinURL)

                VStack(alignment: .leading, spacing: tokens.spacing.small) {
                    Text("Session active")
                        .font(.headline)

                    LabeledContent("Status", value: "Connected")
                    LabeledContent("Devices", value: model.remoteControlConnectedDeviceLabel)
                    LabeledContent("Token expires", value: remoteTimestamp(session.joinTokenLease.expiresAt))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(session.joinURL.absoluteString)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)

            HStack(spacing: tokens.spacing.small) {
                Button("Copy Link") {
                    model.copyRemoteControlJoinLink()
                }

                Button("Stop Session", role: .destructive) {
                    model.stopRemoteControlSession()
                }
            }
        }
    }

    private var inactiveSessionView: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.medium) {
            Text("No active remote session")
                .font(.headline)

            Text("Start a session to generate a one-time QR join link.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Start Session") {
                model.startRemoteControlSession()
            }
        }
    }

    private func qrCodeCard(url: URL) -> some View {
        VStack(alignment: .leading, spacing: tokens.spacing.small) {
            if let image = qrCodeImage(for: url.absoluteString) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .padding(tokens.spacing.small)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.black.opacity(0.08), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 180, height: 180)
                    .overlay(
                        Label("Unable to render QR", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
            }
        }
    }

    private func qrCodeImage(for value: String) -> NSImage? {
        guard let data = value.data(using: .utf8) else {
            return nil
        }

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let representation = NSCIImageRep(ciImage: scaledImage)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }

    private func remoteTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
