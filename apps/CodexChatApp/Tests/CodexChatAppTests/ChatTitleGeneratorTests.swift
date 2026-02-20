@testable import CodexChatShared
import XCTest

final class ChatTitleGeneratorTests: XCTestCase {
    func testRequestPayloadUsesProvidedModel() {
        let payload = ChatTitleGenerator.requestPayload(
            userText: "Summarize this",
            model: "gpt-5-codex",
            reasoningEffort: nil
        )

        XCTAssertEqual(payload["model"] as? String, "gpt-5-codex")
        XCTAssertNil(payload["reasoning"])
    }

    func testRequestPayloadIncludesReasoningWhenProvided() {
        let payload = ChatTitleGenerator.requestPayload(
            userText: "Summarize this",
            model: "gpt-5-codex",
            reasoningEffort: " low "
        )

        let reasoning = payload["reasoning"] as? [String: String]
        XCTAssertEqual(reasoning?["effort"], "low")
    }

    func testNormalizedTitleRemovesFormattingAndTrailingPunctuation() {
        let title = ChatTitleGenerator.normalizedTitle("  \"Plan CI migration today!!!\"  ")

        XCTAssertEqual(title, "Plan CI migration today")
    }

    func testNormalizedTitleRejectsSingleWord() {
        let title = ChatTitleGenerator.normalizedTitle("Refactor")

        XCTAssertNil(title)
    }

    func testNormalizedTitleTruncatesToFiveWords() {
        let title = ChatTitleGenerator.normalizedTitle("Fix stale runtime thread mapping issue quickly")

        XCTAssertEqual(title, "Fix stale runtime thread mapping")
    }

    func testExtractRawTitlePrefersOutputText() {
        let response: [String: Any] = [
            "output_text": "Resolve Sidebar Selection",
            "output": [
                [
                    "content": [
                        ["text": "Fallback title"],
                    ],
                ],
            ],
        ]

        XCTAssertEqual(ChatTitleGenerator.extractRawTitle(from: response), "Resolve Sidebar Selection")
    }

    func testExtractRawTitleFallsBackToContentText() {
        let response: [String: Any] = [
            "output": [
                [
                    "content": [
                        ["text": "Project trust defaults"],
                    ],
                ],
            ],
        ]

        XCTAssertEqual(ChatTitleGenerator.extractRawTitle(from: response), "Project trust defaults")
    }

    func testExtractRawTitleFallsBackToContentOutputText() {
        let response: [String: Any] = [
            "output": [
                [
                    "content": [
                        ["output_text": "Folder icon hover behavior"],
                    ],
                ],
            ],
        ]

        XCTAssertEqual(ChatTitleGenerator.extractRawTitle(from: response), "Folder icon hover behavior")
    }
}
