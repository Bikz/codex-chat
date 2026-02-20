@testable import CodexChatShared
import CodexKit
import XCTest

@MainActor
final class AppModelChatGPTSignInStateTests: XCTestCase {
    func testIsSignedInWithChatGPTWhenAuthModeIsChatGPT() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.accountState = RuntimeAccountState(
            account: RuntimeAccountSummary(type: "apikey", email: nil, planType: nil),
            authMode: .chatGPT,
            requiresOpenAIAuth: true
        )

        XCTAssertTrue(model.isSignedInWithChatGPT)
    }

    func testIsSignedInWithChatGPTWhenAccountTypeIsChatGPTCaseInsensitive() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.accountState = RuntimeAccountState(
            account: RuntimeAccountSummary(type: "ChatGPT", email: nil, planType: nil),
            authMode: .apiKey,
            requiresOpenAIAuth: true
        )

        XCTAssertTrue(model.isSignedInWithChatGPT)
    }

    func testIsSignedInWithChatGPTIsFalseForAPIKeyOnlyState() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.accountState = RuntimeAccountState(
            account: RuntimeAccountSummary(type: "apikey", email: nil, planType: nil),
            authMode: .apiKey,
            requiresOpenAIAuth: true
        )

        XCTAssertFalse(model.isSignedInWithChatGPT)
    }
}
