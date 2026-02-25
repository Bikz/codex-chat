import Foundation
import Security

public protocol RemoteControlDateProvider: Sendable {
    func now() -> Date
}

public struct SystemRemoteControlDateProvider: RemoteControlDateProvider {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

public protocol RemoteControlRandomDataSource: Sendable {
    func randomData(count: Int) throws -> Data
}

public struct SecureRemoteControlRandomDataSource: RemoteControlRandomDataSource {
    public init() {}

    public func randomData(count: Int) throws -> Data {
        guard count > 0 else {
            return Data()
        }

        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw RemoteControlSecurityError.randomSourceUnavailable(status)
        }
        return Data(bytes)
    }
}

public enum RemoteControlSecurityError: Error, LocalizedError {
    case invalidByteCount(Int)
    case randomSourceUnavailable(OSStatus)
    case invalidBaseURL(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidByteCount(count):
            "Requested random token byte count must be > 0 (received \(count))."
        case let .randomSourceUnavailable(status):
            "Secure random generator failed with OSStatus \(status)."
        case let .invalidBaseURL(raw):
            "Invalid pairing base URL: \(raw)."
        }
    }
}

public struct RemoteControlPairingSecurityPolicy: Sendable, Equatable {
    public var joinTokenTTL: TimeInterval
    public var idleTimeout: TimeInterval

    public init(joinTokenTTL: TimeInterval = 120, idleTimeout: TimeInterval = 1800) {
        self.joinTokenTTL = max(10, joinTokenTTL)
        self.idleTimeout = max(60, idleTimeout)
    }
}

public struct RemoteControlJoinTokenLease: Sendable, Equatable {
    public var token: String
    public var issuedAt: Date
    public var expiresAt: Date
    public var usedAt: Date?

    public init(token: String, issuedAt: Date, expiresAt: Date, usedAt: Date? = nil) {
        self.token = token
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.usedAt = usedAt
    }

    public func isExpired(now: Date) -> Bool {
        now >= expiresAt
    }

    public func isUsable(now: Date) -> Bool {
        usedAt == nil && !isExpired(now: now)
    }

    public mutating func markUsed(at timestamp: Date) {
        usedAt = timestamp
    }
}

public struct RemoteControlSessionDescriptor: Sendable, Equatable {
    public var sessionID: String
    public var joinTokenLease: RemoteControlJoinTokenLease
    public var joinURL: URL
    public var relayWebSocketURL: URL
    public var desktopSessionToken: String
    public var createdAt: Date
    public var idleTimeout: TimeInterval

    public init(
        sessionID: String,
        joinTokenLease: RemoteControlJoinTokenLease,
        joinURL: URL,
        relayWebSocketURL: URL,
        desktopSessionToken: String,
        createdAt: Date,
        idleTimeout: TimeInterval
    ) {
        self.sessionID = sessionID
        self.joinTokenLease = joinTokenLease
        self.joinURL = joinURL
        self.relayWebSocketURL = relayWebSocketURL
        self.desktopSessionToken = desktopSessionToken
        self.createdAt = createdAt
        self.idleTimeout = idleTimeout
    }
}

public struct RemoteControlTokenFactory: Sendable {
    private let currentDate: @Sendable () -> Date
    private let randomData: @Sendable (Int) throws -> Data

    public init(
        dateProvider: any RemoteControlDateProvider = SystemRemoteControlDateProvider(),
        randomDataSource: any RemoteControlRandomDataSource = SecureRemoteControlRandomDataSource()
    ) {
        currentDate = { dateProvider.now() }
        randomData = { count in
            try randomDataSource.randomData(count: count)
        }
    }

    public init(
        currentDate: @escaping @Sendable () -> Date,
        randomData: @escaping @Sendable (Int) throws -> Data
    ) {
        self.currentDate = currentDate
        self.randomData = randomData
    }

    public func makeOpaqueToken(byteCount: Int = 32) throws -> String {
        guard byteCount > 0 else {
            throw RemoteControlSecurityError.invalidByteCount(byteCount)
        }
        let bytes = try randomData(byteCount)
        return bytes.base64URLString()
    }

    public func makeSessionID(byteCount: Int = 16) throws -> String {
        try makeOpaqueToken(byteCount: byteCount)
    }

    public func makeJoinTokenLease(ttl: TimeInterval) throws -> RemoteControlJoinTokenLease {
        let issuedAt = currentDate()
        return try RemoteControlJoinTokenLease(
            token: makeOpaqueToken(byteCount: 32),
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(max(10, ttl))
        )
    }

    public func makeSessionDescriptor(
        joinBaseURL: URL,
        relayWebSocketURL: URL,
        policy: RemoteControlPairingSecurityPolicy = .init()
    ) throws -> RemoteControlSessionDescriptor {
        let createdAt = currentDate()
        let sessionID = try makeSessionID()
        let joinTokenLease = try makeJoinTokenLease(ttl: policy.joinTokenTTL)
        let desktopSessionToken = try makeOpaqueToken(byteCount: 32)

        guard var components = URLComponents(url: joinBaseURL, resolvingAgainstBaseURL: false) else {
            throw RemoteControlSecurityError.invalidBaseURL(joinBaseURL.absoluteString)
        }

        if components.path.isEmpty {
            components.path = "/"
        }
        components.query = nil

        var fragmentItems = [
            "sid=\(sessionID)",
            "jt=\(joinTokenLease.token)",
        ]
        if let relayBaseURL = Self.relayBaseURLString(from: relayWebSocketURL) {
            fragmentItems.append("relay=\(relayBaseURL)")
        }
        components.fragment = fragmentItems.joined(separator: "&")

        guard let joinURL = components.url else {
            throw RemoteControlSecurityError.invalidBaseURL(joinBaseURL.absoluteString)
        }

        return RemoteControlSessionDescriptor(
            sessionID: sessionID,
            joinTokenLease: joinTokenLease,
            joinURL: joinURL,
            relayWebSocketURL: relayWebSocketURL,
            desktopSessionToken: desktopSessionToken,
            createdAt: createdAt,
            idleTimeout: policy.idleTimeout
        )
    }

    public static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs.utf8.count == rhs.utf8.count else {
            return false
        }

        var diff: UInt8 = 0
        for (lhsByte, rhsByte) in zip(lhs.utf8, rhs.utf8) {
            diff |= lhsByte ^ rhsByte
        }
        return diff == 0
    }

    private static func relayBaseURLString(from relayWebSocketURL: URL) -> String? {
        guard var components = URLComponents(url: relayWebSocketURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if components.scheme == "wss" {
            components.scheme = "https"
        } else if components.scheme == "ws" {
            components.scheme = "http"
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private extension Data {
    func base64URLString() -> String {
        let base64 = base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
