@testable import CodexChatShared
import CodexKit
import XCTest

@MainActor
final class RuntimeDefaultsAutoModeTests: XCTestCase {
    func testRuntimeTurnOptionsAutoModeOmitsReasoningEffortOverride() {
        let model = makeModel()
        model.runtimeModelCatalog = [
            RuntimeModelInfo(
                id: "gpt-5.3-codex",
                model: "gpt-5.3-codex",
                displayName: "GPT-5.3 Codex",
                supportedReasoningEfforts: [
                    RuntimeReasoningEffortOption(reasoningEffort: "low"),
                    RuntimeReasoningEffortOption(reasoningEffort: "high"),
                ],
                defaultReasoningEffort: "high",
                isDefault: true
            ),
        ]

        model.replaceCodexConfigDocument(.empty())

        XCTAssertEqual(model.defaultModel, "gpt-5.3-codex")
        XCTAssertEqual(model.defaultReasoning, .high)
        XCTAssertNil(model.configuredReasoningOverride())
        XCTAssertNil(model.runtimeTurnOptions().effort)
    }

    func testRuntimeTurnOptionsUsesExplicitReasoningOverrideWhenConfigured() {
        let model = makeModel()
        model.runtimeModelCatalog = [
            RuntimeModelInfo(
                id: "gpt-5.3-codex",
                model: "gpt-5.3-codex",
                displayName: "GPT-5.3 Codex",
                supportedReasoningEfforts: [
                    RuntimeReasoningEffortOption(reasoningEffort: "low"),
                    RuntimeReasoningEffortOption(reasoningEffort: "high"),
                ],
                defaultReasoningEffort: "high",
                isDefault: true
            ),
        ]

        model.updateCodexConfigValue(path: [.key("model_reasoning_effort")], value: .string("low"))

        XCTAssertEqual(model.runtimeTurnOptions().effort, "low")
    }

    private func makeModel() -> AppModel {
        AppModel(repositories: nil, runtime: nil, bootError: nil)
    }
}
