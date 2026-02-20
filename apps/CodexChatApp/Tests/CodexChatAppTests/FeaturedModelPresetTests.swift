@testable import CodexChatShared
import CodexKit
import XCTest

@MainActor
final class FeaturedModelPresetTests: XCTestCase {
    func testFeaturedModelPresetsUsePreferredCodexOrderAndIncludeGPT4o() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.runtimeModelCatalog = [
            RuntimeModelInfo(id: "gpt-5.2-codex", model: "gpt-5.2-codex", displayName: "GPT-5.2 Codex"),
            RuntimeModelInfo(id: "gpt-5.3-codex-spark", model: "gpt-5.3-codex-spark", displayName: "GPT-5.3 Codex Spark"),
            RuntimeModelInfo(id: "gpt-5.3-codex", model: "gpt-5.3-codex", displayName: "GPT-5.3 Codex"),
            RuntimeModelInfo(id: "gpt-5.1-codex-max", model: "gpt-5.1-codex-max", displayName: "GPT-5.1 Codex Max"),
            RuntimeModelInfo(id: "gpt-5.2", model: "gpt-5.2", displayName: "GPT-5.2"),
        ]

        XCTAssertEqual(
            model.featuredModelPresets,
            ["gpt-5.3-codex", "gpt-5.3-codex-spark", "gpt-5.2-codex", "gpt-4o"]
        )
        XCTAssertEqual(model.overflowModelPresets, ["gpt-5.1-codex-max", "gpt-5.2"])
    }

    func testFeaturedModelPresetsDoNotBackfillWithNonFeaturedModels() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.runtimeModelCatalog = [
            RuntimeModelInfo(id: "o3", model: "o3", displayName: "o3"),
            RuntimeModelInfo(id: "gpt-5-mini", model: "gpt-5-mini", displayName: "GPT-5 Mini"),
            RuntimeModelInfo(id: "o4-mini", model: "o4-mini", displayName: "o4-mini"),
        ]

        XCTAssertEqual(model.featuredModelPresets, ["gpt-4o"])
        XCTAssertEqual(model.overflowModelPresets, ["o3", "gpt-5-mini", "o4-mini"])
    }
}
