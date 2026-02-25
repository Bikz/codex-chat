import Foundation

public struct RemoteControlPairStartRequest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var sessionID: String
    public var relayWebSocketURL: String
    public var joinToken: String
    public var joinTokenExpiresAt: Date
    public var desktopSessionToken: String
    public var idleTimeoutSeconds: Int

    public init(
        schemaVersion: Int = RemoteControlProtocol.schemaVersion,
        sessionID: String,
        relayWebSocketURL: String,
        joinToken: String,
        joinTokenExpiresAt: Date,
        desktopSessionToken: String,
        idleTimeoutSeconds: Int
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.relayWebSocketURL = relayWebSocketURL
        self.joinToken = joinToken
        self.joinTokenExpiresAt = joinTokenExpiresAt
        self.desktopSessionToken = desktopSessionToken
        self.idleTimeoutSeconds = idleTimeoutSeconds
    }
}

public struct RemoteControlPairStartResponse: Codable, Sendable, Equatable {
    public var accepted: Bool
    public var relayWebSocketURL: String?

    public init(accepted: Bool, relayWebSocketURL: String? = nil) {
        self.accepted = accepted
        self.relayWebSocketURL = relayWebSocketURL
    }
}

public protocol RemoteControlRelayRegistering: Sendable {
    func startPairing(_ request: RemoteControlPairStartRequest) async throws -> RemoteControlPairStartResponse
}

public struct NoopRemoteControlRelayRegistrar: RemoteControlRelayRegistering {
    public init() {}

    public func startPairing(_ request: RemoteControlPairStartRequest) async throws -> RemoteControlPairStartResponse {
        _ = request
        return RemoteControlPairStartResponse(accepted: true)
    }
}

public enum RemoteControlBrokerPhase: String, Sendable {
    case disconnected
    case active
}

public struct RemoteControlBrokerStatus: Sendable, Equatable {
    public var phase: RemoteControlBrokerPhase
    public var session: RemoteControlSessionDescriptor?
    public var connectedDeviceCount: Int
    public var disconnectReason: String?

    public init(
        phase: RemoteControlBrokerPhase,
        session: RemoteControlSessionDescriptor?,
        connectedDeviceCount: Int,
        disconnectReason: String?
    ) {
        self.phase = phase
        self.session = session
        self.connectedDeviceCount = connectedDeviceCount
        self.disconnectReason = disconnectReason
    }
}

public actor RemoteControlBroker {
    private let relayRegistrar: any RemoteControlRelayRegistering
    private let tokenFactory: RemoteControlTokenFactory
    private var status = RemoteControlBrokerStatus(
        phase: .disconnected,
        session: nil,
        connectedDeviceCount: 0,
        disconnectReason: nil
    )
    private var idleTimeoutTask: Task<Void, Never>?

    public init(
        relayRegistrar: any RemoteControlRelayRegistering = NoopRemoteControlRelayRegistrar(),
        tokenFactory: RemoteControlTokenFactory = RemoteControlTokenFactory()
    ) {
        self.relayRegistrar = relayRegistrar
        self.tokenFactory = tokenFactory
    }

    deinit {
        idleTimeoutTask?.cancel()
    }

    @discardableResult
    public func startSession(
        joinBaseURL: URL,
        relayWebSocketURL: URL,
        policy: RemoteControlPairingSecurityPolicy = .init()
    ) async throws -> RemoteControlSessionDescriptor {
        idleTimeoutTask?.cancel()

        let descriptor = try tokenFactory.makeSessionDescriptor(
            joinBaseURL: joinBaseURL,
            relayWebSocketURL: relayWebSocketURL,
            policy: policy
        )

        let request = RemoteControlPairStartRequest(
            sessionID: descriptor.sessionID,
            relayWebSocketURL: descriptor.relayWebSocketURL.absoluteString,
            joinToken: descriptor.joinTokenLease.token,
            joinTokenExpiresAt: descriptor.joinTokenLease.expiresAt,
            desktopSessionToken: descriptor.desktopSessionToken,
            idleTimeoutSeconds: Int(descriptor.idleTimeout.rounded())
        )
        let relayResponse = try await relayRegistrar.startPairing(request)
        guard relayResponse.accepted else {
            throw URLError(.cannotConnectToHost)
        }

        var effectiveDescriptor = descriptor
        if let relayWebSocketURL = relayResponse.relayWebSocketURL,
           let parsedURL = URL(string: relayWebSocketURL)
        {
            effectiveDescriptor.relayWebSocketURL = parsedURL
        }

        status = RemoteControlBrokerStatus(
            phase: .active,
            session: effectiveDescriptor,
            connectedDeviceCount: 0,
            disconnectReason: nil
        )

        scheduleIdleTimeout(seconds: effectiveDescriptor.idleTimeout)

        return effectiveDescriptor
    }

    public func updateConnectedDeviceCount(_ count: Int) {
        guard status.phase == .active else {
            return
        }
        status.connectedDeviceCount = max(0, count)
        bumpActivity()
    }

    public func consumeJoinToken(_ candidateToken: String, at timestamp: Date = Date()) -> Bool {
        guard var session = status.session else {
            return false
        }
        var lease = session.joinTokenLease
        guard lease.isUsable(now: timestamp) else {
            return false
        }
        guard RemoteControlTokenFactory.constantTimeEquals(lease.token, candidateToken) else {
            return false
        }

        lease.markUsed(at: timestamp)
        session.joinTokenLease = lease
        status.session = session
        bumpActivity()
        return true
    }

    public func stopSession(reason: String = "Stopped by user") {
        idleTimeoutTask?.cancel()
        idleTimeoutTask = nil
        status = RemoteControlBrokerStatus(
            phase: .disconnected,
            session: nil,
            connectedDeviceCount: 0,
            disconnectReason: reason
        )
    }

    public func currentStatus() -> RemoteControlBrokerStatus {
        status
    }

    public func bumpActivity() {
        guard let session = status.session else {
            return
        }
        scheduleIdleTimeout(seconds: session.idleTimeout)
    }

    private func scheduleIdleTimeout(seconds: TimeInterval) {
        idleTimeoutTask?.cancel()
        idleTimeoutTask = Task { [weak self] in
            guard !Task.isCancelled else {
                return
            }
            let nanoseconds = UInt64(max(1, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else {
                return
            }
            await self?.stopSession(reason: "Idle timeout")
        }
    }
}
