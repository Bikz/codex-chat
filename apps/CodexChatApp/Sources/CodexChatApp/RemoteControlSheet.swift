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

            if let request = model.remoteControlPendingPairRequest {
                pendingPairRequestView(request: request)
            }

            Toggle("Allow approvals from remote", isOn: $model.allowRemoteApprovals)
                .help("When enabled, paired remote clients can approve or decline pending actions.")

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

            trustedDevicesSection
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

    private func pendingPairRequestView(request: RemoteControlPairRequestPrompt) -> some View {
        VStack(alignment: .leading, spacing: tokens.spacing.small) {
            Label("Pairing approval needed", systemImage: "hand.raised.fill")
                .font(.headline)

            if let requesterIP = request.requesterIP,
               !requesterIP.isEmpty
            {
                Text("Request from: \(requesterIP)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Request from: Unknown network address")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let expiresAt = request.expiresAt {
                Text("Expires at: \(remoteTimestamp(expiresAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: tokens.spacing.small) {
                Button("Approve") {
                    model.approveRemoteControlPairRequest()
                }
                .buttonStyle(.borderedProminent)

                Button("Deny", role: .destructive) {
                    model.denyRemoteControlPairRequest()
                }
            }
        }
        .padding(tokens.spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.orange.opacity(0.25), lineWidth: 1)
        )
    }

    private var trustedDevicesSection: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.small) {
            Text("Trusted Devices")
                .font(.headline)

            if model.remoteControlStatus.trustedDevices.isEmpty {
                Text("No trusted devices paired yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.remoteControlStatus.trustedDevices) { device in
                    HStack(alignment: .top, spacing: tokens.spacing.small) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.deviceName)
                                .font(.subheadline.weight(.semibold))
                            Text(device.connected ? "Connected now" : "Offline")
                                .font(.caption)
                                .foregroundStyle(device.connected ? .green : .secondary)
                            Text("Last seen \(remoteTimestamp(device.lastSeenAt))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: tokens.spacing.small)
                        Button("Revoke", role: .destructive) {
                            model.revokeRemoteControlTrustedDevice(device.deviceID)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
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
