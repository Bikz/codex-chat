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

public struct RemoteControlPairRefreshRequest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var sessionID: String
    public var relayWebSocketURL: String
    public var joinToken: String
    public var joinTokenExpiresAt: Date
    public var desktopSessionToken: String

    public init(
        schemaVersion: Int = RemoteControlProtocol.schemaVersion,
        sessionID: String,
        relayWebSocketURL: String,
        joinToken: String,
        joinTokenExpiresAt: Date,
        desktopSessionToken: String
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.relayWebSocketURL = relayWebSocketURL
        self.joinToken = joinToken
        self.joinTokenExpiresAt = joinTokenExpiresAt
        self.desktopSessionToken = desktopSessionToken
    }
}

public struct RemoteControlPairRefreshResponse: Codable, Sendable, Equatable {
    public var accepted: Bool
    public var relayWebSocketURL: String?

    public init(accepted: Bool, relayWebSocketURL: String? = nil) {
        self.accepted = accepted
        self.relayWebSocketURL = relayWebSocketURL
    }
}

public struct RemoteControlPairStopRequest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var sessionID: String
    public var relayWebSocketURL: String
    public var desktopSessionToken: String

    public init(
        schemaVersion: Int = RemoteControlProtocol.schemaVersion,
        sessionID: String,
        relayWebSocketURL: String,
        desktopSessionToken: String
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.relayWebSocketURL = relayWebSocketURL
        self.desktopSessionToken = desktopSessionToken
    }
}

public struct RemoteControlPairStopResponse: Codable, Sendable, Equatable {
    public var accepted: Bool

    public init(accepted: Bool) {
        self.accepted = accepted
    }
}

public struct RemoteControlTrustedDevice: Codable, Sendable, Equatable, Identifiable {
    public var deviceID: String
    public var deviceName: String
    public var connected: Bool
    public var joinedAt: Date
    public var lastSeenAt: Date

    public var id: String {
        deviceID
    }

    public init(
        deviceID: String,
        deviceName: String,
        connected: Bool,
        joinedAt: Date,
        lastSeenAt: Date
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.connected = connected
        self.joinedAt = joinedAt
        self.lastSeenAt = lastSeenAt
    }
}

public struct RemoteControlDevicesListRequest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var sessionID: String
    public var relayWebSocketURL: String
    public var desktopSessionToken: String

    public init(
        schemaVersion: Int = RemoteControlProtocol.schemaVersion,
        sessionID: String,
        relayWebSocketURL: String,
        desktopSessionToken: String
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.relayWebSocketURL = relayWebSocketURL
        self.desktopSessionToken = desktopSessionToken
    }
}

public struct RemoteControlDevicesListResponse: Codable, Sendable, Equatable {
    public var accepted: Bool
    public var devices: [RemoteControlTrustedDevice]

    public init(accepted: Bool, devices: [RemoteControlTrustedDevice]) {
        self.accepted = accepted
        self.devices = devices
    }
}

public struct RemoteControlDeviceRevokeRequest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var sessionID: String
    public var relayWebSocketURL: String
    public var desktopSessionToken: String
    public var deviceID: String

    public init(
        schemaVersion: Int = RemoteControlProtocol.schemaVersion,
        sessionID: String,
        relayWebSocketURL: String,
        desktopSessionToken: String,
        deviceID: String
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.relayWebSocketURL = relayWebSocketURL
        self.desktopSessionToken = desktopSessionToken
        self.deviceID = deviceID
    }
}

public struct RemoteControlDeviceRevokeResponse: Codable, Sendable, Equatable {
    public var accepted: Bool

    public init(accepted: Bool) {
        self.accepted = accepted
    }
}

public protocol RemoteControlRelayRegistering: Sendable {
    func startPairing(_ request: RemoteControlPairStartRequest) async throws -> RemoteControlPairStartResponse
    func refreshPairing(_ request: RemoteControlPairRefreshRequest) async throws -> RemoteControlPairRefreshResponse
    func stopPairing(_ request: RemoteControlPairStopRequest) async throws -> RemoteControlPairStopResponse
    func listDevices(_ request: RemoteControlDevicesListRequest) async throws -> RemoteControlDevicesListResponse
    func revokeDevice(_ request: RemoteControlDeviceRevokeRequest) async throws -> RemoteControlDeviceRevokeResponse
}

public struct NoopRemoteControlRelayRegistrar: RemoteControlRelayRegistering {
    public init() {}

    public func startPairing(_ request: RemoteControlPairStartRequest) async throws -> RemoteControlPairStartResponse {
        _ = request
        return RemoteControlPairStartResponse(accepted: true)
    }

    public func refreshPairing(_ request: RemoteControlPairRefreshRequest) async throws -> RemoteControlPairRefreshResponse {
        _ = request
        return RemoteControlPairRefreshResponse(accepted: true)
    }

    public func stopPairing(_ request: RemoteControlPairStopRequest) async throws -> RemoteControlPairStopResponse {
        _ = request
        return RemoteControlPairStopResponse(accepted: true)
    }

    public func listDevices(_ request: RemoteControlDevicesListRequest) async throws -> RemoteControlDevicesListResponse {
        _ = request
        return RemoteControlDevicesListResponse(accepted: true, devices: [])
    }

    public func revokeDevice(_ request: RemoteControlDeviceRevokeRequest) async throws -> RemoteControlDeviceRevokeResponse {
        _ = request
        return RemoteControlDeviceRevokeResponse(accepted: true)
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
    public var trustedDevices: [RemoteControlTrustedDevice]
    public var disconnectReason: String?

    public init(
        phase: RemoteControlBrokerPhase,
        session: RemoteControlSessionDescriptor?,
        connectedDeviceCount: Int,
        trustedDevices: [RemoteControlTrustedDevice] = [],
        disconnectReason: String?
    ) {
        self.phase = phase
        self.session = session
        self.connectedDeviceCount = connectedDeviceCount
        self.trustedDevices = trustedDevices
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
        trustedDevices: [],
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
            trustedDevices: [],
            disconnectReason: nil
        )

        scheduleIdleTimeout(seconds: effectiveDescriptor.idleTimeout)

        return effectiveDescriptor
    }

    @discardableResult
    public func refreshJoinToken(
        joinBaseURL: URL,
        policy: RemoteControlPairingSecurityPolicy = .init()
    ) async throws -> RemoteControlSessionDescriptor {
        guard var session = status.session else {
            throw URLError(.badURL)
        }

        let refreshedLease = try tokenFactory.makeJoinTokenLease(ttl: policy.joinTokenTTL)
        let refreshedJoinURL = try tokenFactory.makeJoinURL(
            joinBaseURL: joinBaseURL,
            relayWebSocketURL: session.relayWebSocketURL,
            sessionID: session.sessionID,
            joinToken: refreshedLease.token
        )
        let request = RemoteControlPairRefreshRequest(
            sessionID: session.sessionID,
            relayWebSocketURL: session.relayWebSocketURL.absoluteString,
            joinToken: refreshedLease.token,
            joinTokenExpiresAt: refreshedLease.expiresAt,
            desktopSessionToken: session.desktopSessionToken
        )
        let relayResponse = try await relayRegistrar.refreshPairing(request)
        guard relayResponse.accepted else {
            throw URLError(.cannotConnectToHost)
        }

        if let relayWebSocketURL = relayResponse.relayWebSocketURL,
           let parsedURL = URL(string: relayWebSocketURL)
        {
            session.relayWebSocketURL = parsedURL
        }
        session.joinTokenLease = refreshedLease
        session.joinURL = refreshedJoinURL
        status.session = session
        bumpActivity()
        return session
    }

    public func updateConnectedDeviceCount(_ count: Int) {
        guard status.phase == .active else {
            return
        }
        status.connectedDeviceCount = max(0, count)
        bumpActivity()
    }

    @discardableResult
    public func refreshTrustedDevices() async throws -> [RemoteControlTrustedDevice] {
        guard let session = status.session else {
            status.trustedDevices = []
            status.connectedDeviceCount = 0
            return []
        }

        let request = RemoteControlDevicesListRequest(
            sessionID: session.sessionID,
            relayWebSocketURL: session.relayWebSocketURL.absoluteString,
            desktopSessionToken: session.desktopSessionToken
        )
        let response = try await relayRegistrar.listDevices(request)
        guard response.accepted else {
            throw URLError(.cannotConnectToHost)
        }

        status.trustedDevices = response.devices
        status.connectedDeviceCount = response.devices.filter(\.connected).count
        bumpActivity()
        return response.devices
    }

    public func revokeTrustedDevice(deviceID: String) async throws {
        guard let session = status.session else {
            throw URLError(.badURL)
        }

        let request = RemoteControlDeviceRevokeRequest(
            sessionID: session.sessionID,
            relayWebSocketURL: session.relayWebSocketURL.absoluteString,
            desktopSessionToken: session.desktopSessionToken,
            deviceID: deviceID
        )
        let response = try await relayRegistrar.revokeDevice(request)
        guard response.accepted else {
            throw URLError(.cannotConnectToHost)
        }

        status.trustedDevices.removeAll(where: { $0.deviceID == deviceID })
        status.connectedDeviceCount = status.trustedDevices.filter(\.connected).count
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

    public func stopSession(reason: String = "Stopped by user") async {
        idleTimeoutTask?.cancel()
        idleTimeoutTask = nil

        if let session = status.session {
            let request = RemoteControlPairStopRequest(
                sessionID: session.sessionID,
                relayWebSocketURL: session.relayWebSocketURL.absoluteString,
                desktopSessionToken: session.desktopSessionToken
            )
            _ = try? await relayRegistrar.stopPairing(request)
        }

        status = RemoteControlBrokerStatus(
            phase: .disconnected,
            session: nil,
            connectedDeviceCount: 0,
            trustedDevices: [],
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
