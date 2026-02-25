import AppKit
import CodexChatRemoteControl
import Foundation

extension AppModel {
    private static let defaultRemoteControlJoinURL = "https://remote.codexchat.app/rc"
    private static let defaultRemoteControlRelayWSURL = "wss://remote.codexchat.app/ws"

    var isRemoteControlSessionActive: Bool {
        remoteControlStatus.phase == .active && remoteControlStatus.session != nil
    }

    var remoteControlJoinURL: URL? {
        remoteControlStatus.session?.joinURL
    }

    var remoteControlConnectedDeviceLabel: String {
        Self.remoteControlConnectedDeviceLabel(count: remoteControlStatus.connectedDeviceCount)
    }

    static func remoteControlConnectedDeviceLabel(count: Int) -> String {
        let sanitizedCount = max(0, count)
        let suffix = sanitizedCount == 1 ? "device" : "devices"
        return "\(sanitizedCount) \(suffix) connected"
    }

    func presentRemoteControlSheet() {
        isRemoteControlSheetVisible = true
        Task {
            await refreshRemoteControlStatus()
        }
    }

    func dismissRemoteControlSheet() {
        isRemoteControlSheetVisible = false
    }

    func startRemoteControlSession() {
        guard let urls = resolvedRemoteControlURLs() else {
            return
        }

        remoteControlStatusMessage = "Starting remote session..."
        Task { [weak self] in
            guard let self else { return }
            do {
                let descriptor = try await remoteControlBroker.startSession(
                    joinBaseURL: urls.joinURL,
                    relayWebSocketURL: urls.relayWebSocketURL
                )
                await refreshRemoteControlStatus()
                remoteControlStatusMessage = "Remote session started. Join token expires at \(Self.remoteTimestamp(descriptor.joinTokenLease.expiresAt))."
                appendLog(.info, "Remote control session started: \(descriptor.sessionID)")
            } catch {
                await refreshRemoteControlStatus()
                remoteControlStatusMessage = "Unable to start remote session: \(error.localizedDescription)"
                appendLog(.error, "Failed to start remote control session: \(error.localizedDescription)")
            }
        }
    }

    func stopRemoteControlSession() {
        Task { [weak self] in
            guard let self else { return }
            await remoteControlBroker.stopSession(reason: "Stopped by user")
            await refreshRemoteControlStatus()
            remoteControlStatusMessage = "Remote session stopped."
            appendLog(.info, "Remote control session stopped by user")
        }
    }

    func copyRemoteControlJoinLink() {
        guard let joinURL = remoteControlJoinURL else {
            remoteControlStatusMessage = "Start a remote session first to generate a QR link."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(joinURL.absoluteString, forType: .string)
        remoteControlStatusMessage = "Copied remote link to clipboard."
    }

    func refreshRemoteControlStatus() async {
        remoteControlStatus = await remoteControlBroker.currentStatus()
    }

    func updateRemoteControlConnectedDeviceCount(_ count: Int) {
        Task { [weak self] in
            guard let self else { return }
            await remoteControlBroker.updateConnectedDeviceCount(count)
            await refreshRemoteControlStatus()
        }
    }

    private func resolvedRemoteControlURLs() -> (joinURL: URL, relayWebSocketURL: URL)? {
        let joinRaw = ProcessInfo.processInfo.environment["CODEXCHAT_REMOTE_CONTROL_JOIN_URL"]
            ?? Self.defaultRemoteControlJoinURL
        let relayRaw = ProcessInfo.processInfo.environment["CODEXCHAT_REMOTE_CONTROL_RELAY_WS_URL"]
            ?? Self.defaultRemoteControlRelayWSURL

        guard let joinURL = URL(string: joinRaw) else {
            remoteControlStatusMessage = "Invalid CODEXCHAT_REMOTE_CONTROL_JOIN_URL: \(joinRaw)"
            return nil
        }
        guard let relayWebSocketURL = URL(string: relayRaw) else {
            remoteControlStatusMessage = "Invalid CODEXCHAT_REMOTE_CONTROL_RELAY_WS_URL: \(relayRaw)"
            return nil
        }
        return (joinURL, relayWebSocketURL)
    }

    private static func remoteTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
