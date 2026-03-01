import CodexChatRemoteControl
import Foundation

protocol RemoteControlSessionCredentialStoring: Sendable {
    func loadSessionDescriptor() throws -> RemoteControlSessionDescriptor?
    func saveSessionDescriptor(_ descriptor: RemoteControlSessionDescriptor) throws
    func clearSessionDescriptor() throws
}

final class RemoteControlSessionCredentialStore: @unchecked Sendable, RemoteControlSessionCredentialStoring {
    private static let schemaVersion = 1

    private let secrets: any SecretCredentialStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(secrets: any SecretCredentialStoring = APIKeychainStore()) {
        self.secrets = secrets
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSessionDescriptor() throws -> RemoteControlSessionDescriptor? {
        guard let encodedPayload = try secrets.readSecret(account: APIKeychainStore.remoteControlSessionAccount),
              !encodedPayload.isEmpty
        else {
            return nil
        }

        guard let payloadData = Data(base64Encoded: encodedPayload),
              let payload = try? decoder.decode(PersistedRemoteControlSession.self, from: payloadData),
              payload.schemaVersion == Self.schemaVersion
        else {
            try clearSessionDescriptor()
            return nil
        }

        return payload.descriptor
    }

    func saveSessionDescriptor(_ descriptor: RemoteControlSessionDescriptor) throws {
        let payload = PersistedRemoteControlSession(schemaVersion: Self.schemaVersion, descriptor: descriptor)
        let payloadData = try encoder.encode(payload)
        let encodedPayload = payloadData.base64EncodedString()
        try secrets.saveSecret(encodedPayload, account: APIKeychainStore.remoteControlSessionAccount)
    }

    func clearSessionDescriptor() throws {
        try secrets.deleteSecret(account: APIKeychainStore.remoteControlSessionAccount)
    }
}

private struct PersistedRemoteControlSession: Codable {
    let schemaVersion: Int
    let sessionID: String
    let joinToken: String
    let joinTokenIssuedAt: Date
    let joinTokenExpiresAt: Date
    let joinTokenUsedAt: Date?
    let joinURL: URL
    let relayWebSocketURL: URL
    let desktopSessionToken: String
    let createdAt: Date
    let idleTimeoutSeconds: TimeInterval

    init(schemaVersion: Int, descriptor: RemoteControlSessionDescriptor) {
        self.schemaVersion = schemaVersion
        sessionID = descriptor.sessionID
        joinToken = descriptor.joinTokenLease.token
        joinTokenIssuedAt = descriptor.joinTokenLease.issuedAt
        joinTokenExpiresAt = descriptor.joinTokenLease.expiresAt
        joinTokenUsedAt = descriptor.joinTokenLease.usedAt
        joinURL = descriptor.joinURL
        relayWebSocketURL = descriptor.relayWebSocketURL
        desktopSessionToken = descriptor.desktopSessionToken
        createdAt = descriptor.createdAt
        idleTimeoutSeconds = descriptor.idleTimeout
    }

    var descriptor: RemoteControlSessionDescriptor {
        RemoteControlSessionDescriptor(
            sessionID: sessionID,
            joinTokenLease: RemoteControlJoinTokenLease(
                token: joinToken,
                issuedAt: joinTokenIssuedAt,
                expiresAt: joinTokenExpiresAt,
                usedAt: joinTokenUsedAt
            ),
            joinURL: joinURL,
            relayWebSocketURL: relayWebSocketURL,
            desktopSessionToken: desktopSessionToken,
            createdAt: createdAt,
            idleTimeout: idleTimeoutSeconds
        )
    }
}
