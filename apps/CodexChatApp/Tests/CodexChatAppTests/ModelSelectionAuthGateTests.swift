@testable import CodexChatShared
import CodexKit
import XCTest

@MainActor
final class ModelSelectionAuthGateTests: XCTestCase {
    func testModelMenuLabelUsesDisplayNameWithoutModelIDSuffix() {
        let model = makeModel()
        model.runtimeModelCatalog = [
            RuntimeModelInfo(
                id: "gpt-5.3-codex",
                model: "gpt-5.3-codex",
                displayName: "GPT-5.3-Codex"
            ),
        ]

        XCTAssertEqual(model.modelMenuLabel(for: "gpt-5.3-codex"), "GPT-5.3-Codex")
    }

    func testModelMenuLabelMarksGPT4oAsAPIKeyOnly() {
        let model = makeModel()

        XCTAssertEqual(model.modelMenuLabel(for: "gpt-4o"), "gpt-4o (api key only)")
    }

    func testSetDefaultModelGPT4oWithChatGPTAuthShowsAPIKeyPromptAndKeepsExistingModel() {
        let model = makeModel()
        model.updateCodexConfigValue(path: [.key("model")], value: .string("gpt-5.3-codex"))
        model.accountState = RuntimeAccountState(
            account: RuntimeAccountSummary(type: "chatgpt", email: "dev@example.com", planType: "plus"),
            authMode: .chatGPT,
            requiresOpenAIAuth: true
        )

        model.setDefaultModel("gpt-4o")

        XCTAssertTrue(model.isAPIKeyPromptVisible)
        XCTAssertTrue(model.accountStatusMessage?.contains("requires API key login") ?? false)
        XCTAssertEqual(model.defaultModel, "gpt-5.3-codex")
        XCTAssertEqual(
            model.codexConfigDocument.value(at: [.key("model")])?.stringValue,
            "gpt-5.3-codex"
        )
    }

    func testSetDefaultModelGPT4oWithAPIKeyAuthAllowsSelection() {
        let model = makeModel()
        model.accountState = RuntimeAccountState(
            account: RuntimeAccountSummary(type: "apikey", email: nil, planType: nil),
            authMode: .apiKey,
            requiresOpenAIAuth: true
        )

        model.setDefaultModel("gpt-4o")

        XCTAssertFalse(model.isAPIKeyPromptVisible)
        XCTAssertEqual(model.defaultModel, "gpt-4o")
        XCTAssertEqual(model.codexConfigDocument.value(at: [.key("model")])?.stringValue, "gpt-4o")
    }

    private func makeModel() -> AppModel {
        AppModel(repositories: nil, runtime: nil, bootError: nil)
    }
}
