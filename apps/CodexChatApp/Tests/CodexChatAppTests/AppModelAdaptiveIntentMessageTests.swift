@testable import CodexChatShared
import XCTest

@MainActor
final class AppModelAdaptiveIntentMessageTests: XCTestCase {
    func testParsesImessageToRecipientSayingBody() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let intent = model.adaptiveIntent(
            for: "send an iMessage to +16502509815 saying hello from codex"
        )

        XCTAssertEqual(
            intent,
            .messagesSend(recipient: "+16502509815", body: "hello from codex")
        )
    }

    func testParsesPoliteMessagePromptWithSeparator() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let intent = model.adaptiveIntent(
            for: "Can you send message to Alice: Running 5 min late."
        )

        XCTAssertEqual(
            intent,
            .messagesSend(recipient: "Alice", body: "Running 5 min late.")
        )
    }

    func testParsesQuotedTextRecipientAndBody() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let intent = model.adaptiveIntent(
            for: "please text \"Bob\" saying \"Hey there\""
        )

        XCTAssertEqual(
            intent,
            .messagesSend(recipient: "Bob", body: "Hey there")
        )
    }
}
