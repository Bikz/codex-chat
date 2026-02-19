import CodexChatCore
@testable import CodexChatShared
import CodexKit
import XCTest

final class RuntimeRepairSuggestionTests: XCTestCase {
    @MainActor
    func testRolloutPathWarningEmitsRepairSuggestionAfterThreadMappingResolves() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        let runtimeThreadID = "runtime-thread-delayed-map"

        model.transcriptStore[threadID] = [
            .message(ChatMessage(threadId: threadID, role: .user, text: "List calendar events")),
        ]

        model.handleRuntimeEvent(
            .action(
                RuntimeAction(
                    method: "runtime/stderr",
                    itemID: nil,
                    itemType: nil,
                    threadID: runtimeThreadID,
                    turnID: nil,
                    title: "Runtime stderr",
                    detail: "state db missing rollout path for thread abc"
                )
            )
        )

        let afterWarningCards = actionCards(model.transcriptStore[threadID, default: []])
        XCTAssertFalse(afterWarningCards.contains(where: { $0.method == "runtime/repair-suggested" }))

        model.localThreadIDByRuntimeThreadID[runtimeThreadID] = threadID

        model.handleRuntimeEvent(
            .action(
                RuntimeAction(
                    method: "item/started",
                    itemID: nil,
                    itemType: nil,
                    threadID: runtimeThreadID,
                    turnID: nil,
                    title: "Started",
                    detail: "runtime resumed"
                )
            )
        )

        let finalCards = actionCards(model.transcriptStore[threadID, default: []])
        let repairSuggestions = finalCards.filter { $0.method == "runtime/repair-suggested" }
        XCTAssertEqual(repairSuggestions.count, 1)
    }

    private func actionCards(_ entries: [TranscriptEntry]) -> [ActionCard] {
        entries.compactMap { entry in
            guard case let .actionCard(card) = entry else {
                return nil
            }
            return card
        }
    }
}
