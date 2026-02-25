@testable import CodexChatRemoteControl
import Foundation
import XCTest

private struct FixedDateProvider: RemoteControlDateProvider {
    let fixed: Date

    func now() -> Date {
        fixed
    }
}

private struct IncrementingPatternRandomSource: RemoteControlRandomDataSource {
    func randomData(count: Int) throws -> Data {
        Data((0 ..< count).map { UInt8($0 % 255) })
    }
}

final class RemoteControlSecurityTests: XCTestCase {
    func testJoinTokenLeaseExpiresUsingInjectedClock() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let factory = RemoteControlTokenFactory(
            dateProvider: FixedDateProvider(fixed: fixedNow),
            randomDataSource: IncrementingPatternRandomSource()
        )

        var lease = try factory.makeJoinTokenLease(ttl: 120)
        XCTAssertEqual(lease.issuedAt, fixedNow)
        XCTAssertEqual(lease.expiresAt, fixedNow.addingTimeInterval(120))
        XCTAssertTrue(lease.isUsable(now: fixedNow.addingTimeInterval(119)))
        XCTAssertFalse(lease.isUsable(now: fixedNow.addingTimeInterval(120)))

        lease.markUsed(at: fixedNow.addingTimeInterval(2))
        XCTAssertFalse(lease.isUsable(now: fixedNow.addingTimeInterval(3)))
    }

    func testSessionDescriptorBuildsJoinURLWithFragmentSecret() throws {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let factory = RemoteControlTokenFactory(
            dateProvider: FixedDateProvider(fixed: fixedNow),
            randomDataSource: IncrementingPatternRandomSource()
        )

        let descriptor = try factory.makeSessionDescriptor(
            joinBaseURL: XCTUnwrap(URL(string: "https://remote.codexchat.example")),
            relayWebSocketURL: XCTUnwrap(URL(string: "wss://relay.codexchat.example/ws")),
            policy: RemoteControlPairingSecurityPolicy(joinTokenTTL: 90, idleTimeout: 1800)
        )

        XCTAssertEqual(descriptor.createdAt, fixedNow)
        XCTAssertEqual(descriptor.joinURL.scheme, "https")
        XCTAssertTrue(descriptor.joinURL.absoluteString.contains("#sid="))
        XCTAssertTrue(descriptor.joinURL.absoluteString.contains("&jt="))
        let fragmentQuery = URLComponents(string: "https://example.invalid/?\(descriptor.joinURL.fragment ?? "")")?.queryItems
        XCTAssertEqual(fragmentQuery?.first(where: { $0.name == "relay" })?.value, "https://relay.codexchat.example")
        XCTAssertNil(URLComponents(url: descriptor.joinURL, resolvingAgainstBaseURL: false)?.query)
        XCTAssertFalse(descriptor.desktopSessionToken.isEmpty)
    }

    func testConstantTimeEqualsRejectsDifferentStrings() {
        XCTAssertTrue(RemoteControlTokenFactory.constantTimeEquals("abc123", "abc123"))
        XCTAssertFalse(RemoteControlTokenFactory.constantTimeEquals("abc123", "abc124"))
        XCTAssertFalse(RemoteControlTokenFactory.constantTimeEquals("abc123", "abc1234"))
    }
}
