import CodexChatRemoteControl
@testable import CodexChatShared
import Foundation
import XCTest

private final class InMemorySecretCredentialStore: SecretCredentialStoring, @unchecked Sendable {
    private var secrets: [String: String] = [:]

    func saveSecret(_ secret: String, account: String) throws {
        secrets[account] = secret
    }

    func deleteSecret(account: String) throws {
        secrets.removeValue(forKey: account)
    }

    func readSecret(account: String) throws -> String? {
        secrets[account]
    }
}

final class RemoteControlSessionCredentialStoreTests: XCTestCase {
    func testRoundTripsSessionDescriptor() throws {
        let secrets = InMemorySecretCredentialStore()
        let store = RemoteControlSessionCredentialStore(secrets: secrets)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let joinURL = try XCTUnwrap(URL(string: "https://remote.example/rc#sid=sid&jt=jt"))
        let relayWebSocketURL = try XCTUnwrap(URL(string: "wss://remote.example/ws"))
        let descriptor = RemoteControlSessionDescriptor(
            sessionID: "session-\(UUID().uuidString)",
            joinTokenLease: RemoteControlJoinTokenLease(
                token: "join-token",
                issuedAt: now,
                expiresAt: now.addingTimeInterval(180),
                usedAt: now.addingTimeInterval(15)
            ),
            joinURL: joinURL,
            relayWebSocketURL: relayWebSocketURL,
            desktopSessionToken: "desktop-token",
            createdAt: now,
            idleTimeout: 3600
        )

        try store.saveSessionDescriptor(descriptor)
        let restored = try store.loadSessionDescriptor()

        XCTAssertEqual(restored, descriptor)
    }

    func testInvalidStoredPayloadIsPurged() throws {
        let secrets = InMemorySecretCredentialStore()
        let store = RemoteControlSessionCredentialStore(secrets: secrets)
        try secrets.saveSecret("not-base64", account: APIKeychainStore.remoteControlSessionAccount)

        let restored = try store.loadSessionDescriptor()
        XCTAssertNil(restored)
        let persisted = try secrets.readSecret(account: APIKeychainStore.remoteControlSessionAccount)
        XCTAssertNil(persisted)
    }
}
