import CodexChatCore
@testable import CodexChatShared
import XCTest

final class TranscriptPresentationTests: XCTestCase {
    func testChatModeCompactsLifecycleActionsIntoTurnSummary() {
        let threadID = UUID()
        let entries: [TranscriptEntry] = [
            .message(userMessage(threadID: threadID, text: "Plan my day")),
            .actionCard(action(threadID: threadID, method: "turn/started", title: "Turn started")),
            .actionCard(action(threadID: threadID, method: "item/started", title: "Started reasoning")),
            .actionCard(action(threadID: threadID, method: "item/completed", title: "Completed reasoning")),
            .actionCard(action(threadID: threadID, method: "turn/completed", title: "Turn completed")),
        ]

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: .chat,
            activeTurnContext: nil
        )

        XCTAssertEqual(rows.messageCount, 1)
        XCTAssertEqual(rows.turnSummaryCount, 1)
        XCTAssertEqual(rows.actionMethods, [])
    }

    func testBalancedModeIncludesMilestoneCounts() {
        let threadID = UUID()
        let entries: [TranscriptEntry] = [
            .message(userMessage(threadID: threadID, text: "Check my repo")),
            .actionCard(action(threadID: threadID, method: "item/started", title: "Started reasoning")),
            .actionCard(action(threadID: threadID, method: "item/started", title: "Started commandExecution")),
            .actionCard(action(threadID: threadID, method: "turn/completed", title: "Turn completed")),
        ]

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: .balanced,
            activeTurnContext: nil
        )

        guard case let .turnSummary(summary)? = rows.first(where: {
            if case .turnSummary = $0 { return true }
            return false
        }) else {
            XCTFail("Expected a turn summary row")
            return
        }

        XCTAssertGreaterThan(summary.milestoneCounts.reasoning, 0)
        XCTAssertGreaterThan(summary.milestoneCounts.commandExecution, 0)
    }

    func testDetailedModePreservesRawActionTimeline() {
        let threadID = UUID()
        let entries: [TranscriptEntry] = [
            .message(userMessage(threadID: threadID, text: "Ship release")),
            .actionCard(action(threadID: threadID, method: "turn/started", title: "Turn started")),
            .actionCard(action(threadID: threadID, method: "item/started", title: "Started reasoning")),
            .actionCard(action(threadID: threadID, method: "turn/completed", title: "Turn completed")),
        ]

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: .detailed,
            activeTurnContext: nil
        )

        XCTAssertEqual(rows.actionMethods, ["turn/started", "item/started", "turn/completed"])
    }

    func testCriticalActionsRemainInlineInChatMode() {
        let threadID = UUID()
        let entries: [TranscriptEntry] = [
            .message(userMessage(threadID: threadID, text: "Run dangerous command")),
            .actionCard(action(threadID: threadID, method: "approval/reset", title: "Approval reset")),
            .actionCard(action(threadID: threadID, method: "turn/start/error", title: "Turn failed to start")),
        ]

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: .chat,
            activeTurnContext: nil
        )

        XCTAssertTrue(rows.actionMethods.contains("approval/reset"))
        XCTAssertTrue(rows.actionMethods.contains("turn/start/error"))
    }

    func testChatModeCoalescesRepeatedNonCriticalRuntimeStderr() {
        let threadID = UUID()
        let stderrDetail = "2026-02-19T06:29:52.182126Z warning temporary network jitter"
        let entries: [TranscriptEntry] = [
            .message(userMessage(threadID: threadID, text: "List calendar events")),
            .actionCard(action(threadID: threadID, method: "runtime/stderr", title: "Runtime stderr", detail: stderrDetail)),
            .actionCard(action(threadID: threadID, method: "runtime/stderr", title: "Runtime stderr", detail: stderrDetail)),
            .actionCard(action(threadID: threadID, method: "runtime/stderr", title: "Runtime stderr", detail: stderrDetail)),
            .actionCard(action(threadID: threadID, method: "runtime/stderr", title: "Runtime stderr", detail: stderrDetail)),
        ]

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: .chat,
            activeTurnContext: nil
        )

        XCTAssertTrue(rows.actionMethods.contains("runtime/stderr/coalesced"))
        XCTAssertFalse(rows.actionMethods.contains("runtime/stderr"))
    }

    func testRolloutPathRuntimeStderrWithErrorLevelRemainsInline() {
        let threadID = UUID()
        let entries: [TranscriptEntry] = [
            .message(userMessage(threadID: threadID, text: "List calendar events")),
            .actionCard(action(
                threadID: threadID,
                method: "runtime/stderr",
                title: "Runtime stderr",
                detail: "ERROR state db missing rollout path for thread abc"
            )),
        ]

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: .chat,
            activeTurnContext: nil
        )

        XCTAssertTrue(rows.actionMethods.contains("runtime/stderr"))
    }

    func testRolloutPathRuntimeStderrWarningRemainsCompact() {
        let threadID = UUID()
        let entries: [TranscriptEntry] = [
            .message(userMessage(threadID: threadID, text: "List calendar events")),
            .actionCard(action(
                threadID: threadID,
                method: "runtime/stderr",
                title: "Runtime stderr",
                detail: "state db missing rollout path for thread abc"
            )),
        ]

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: .chat,
            activeTurnContext: nil
        )

        XCTAssertFalse(rows.actionMethods.contains("runtime/stderr"))
        XCTAssertFalse(rows.actionMethods.contains("runtime/stderr/coalesced"))
    }

    func testFatalRuntimeStderrRemainsInlineInChatMode() {
        let threadID = UUID()
        let entries: [TranscriptEntry] = [
            .message(userMessage(threadID: threadID, text: "List calendar events")),
            .actionCard(action(
                threadID: threadID,
                method: "runtime/stderr",
                title: "Runtime stderr",
                detail: "fatal: segmentation fault"
            )),
        ]

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: .chat,
            activeTurnContext: nil
        )

        XCTAssertTrue(rows.actionMethods.contains("runtime/stderr"))
    }

    func testChatModeCoalescesRepeatedCriticalRuntimeStderr() {
        let threadID = UUID()
        let stderrDetail = "fatal: segmentation fault"
        let entries: [TranscriptEntry] = [
            .message(userMessage(threadID: threadID, text: "Run command")),
            .actionCard(action(threadID: threadID, method: "runtime/stderr", title: "Runtime stderr", detail: stderrDetail)),
            .actionCard(action(threadID: threadID, method: "runtime/stderr", title: "Runtime stderr", detail: stderrDetail)),
            .actionCard(action(threadID: threadID, method: "runtime/stderr", title: "Runtime stderr", detail: stderrDetail)),
            .actionCard(action(threadID: threadID, method: "runtime/stderr", title: "Runtime stderr", detail: stderrDetail)),
        ]

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: .chat,
            activeTurnContext: nil
        )

        XCTAssertTrue(rows.actionMethods.contains("runtime/stderr/coalesced"))
        XCTAssertFalse(rows.actionMethods.contains("runtime/stderr"))
    }

    @MainActor
    func testLiveActivityRowAppearsWhileTurnIsActive() {
        let threadID = UUID()
        let turnID = UUID()
        let entries: [TranscriptEntry] = [
            .message(userMessage(threadID: threadID, text: "Summarize this repo")),
        ]

        let activeContext = AppModel.ActiveTurnContext(
            localTurnID: turnID,
            localThreadID: threadID,
            projectID: UUID(),
            projectPath: "/tmp",
            runtimeThreadID: "runtime-thread",
            runtimeTurnID: "runtime-turn",
            memoryWriteMode: .off,
            userText: "Summarize this repo",
            assistantText: "Analyzing files…",
            actions: [
                action(
                    threadID: threadID,
                    method: "item/started",
                    title: "Started reasoning"
                ),
            ],
            startedAt: Date()
        )

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: .chat,
            activeTurnContext: activeContext
        )

        let liveRows = rows.filter {
            if case .liveActivity = $0 { return true }
            return false
        }
        XCTAssertEqual(liveRows.count, 1)
    }

    func testCompletedTurnShowsSummaryWithoutLiveActivity() {
        let threadID = UUID()
        let entries: [TranscriptEntry] = [
            .message(userMessage(threadID: threadID, text: "Summarize this repo")),
            .actionCard(action(threadID: threadID, method: "item/started", title: "Started reasoning")),
            .actionCard(action(threadID: threadID, method: "turn/completed", title: "Turn completed")),
        ]

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: .chat,
            activeTurnContext: nil
        )

        XCTAssertEqual(rows.turnSummaryCount, 1)
        XCTAssertFalse(rows.contains {
            if case .liveActivity = $0 { return true }
            return false
        })
    }

    func testCompactRowsUseUniqueRowIdentifiers() {
        let threadID = UUID()
        let entries: [TranscriptEntry] = [
            .message(userMessage(threadID: threadID, text: "Summarize this repo")),
            .actionCard(action(threadID: threadID, method: "turn/completed", title: "Turn completed")),
        ]

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: .chat,
            activeTurnContext: nil
        )

        let ids = rows.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    @MainActor
    func testPresentationCacheHitReturnsIdenticalRowsForUnchangedKey() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        model.selectedThreadID = threadID
        model.appendEntry(.message(userMessage(threadID: threadID, text: "Hello")), to: threadID)

        guard case let .loaded(entries) = model.conversationState else {
            XCTFail("Expected loaded conversation state")
            return
        }

        let first = model.presentationRowsForSelectedConversation(entries: entries)
        let second = model.presentationRowsForSelectedConversation(entries: entries)

        XCTAssertEqual(first, second)
        XCTAssertEqual(model.transcriptPresentationCache.count, 1)
    }

    @MainActor
    func testTranscriptRevisionBumpInvalidatesPresentationCache() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        model.selectedThreadID = threadID
        model.appendEntry(.message(userMessage(threadID: threadID, text: "Hello")), to: threadID)

        guard case let .loaded(initialEntries) = model.conversationState else {
            XCTFail("Expected loaded conversation state")
            return
        }
        _ = model.presentationRowsForSelectedConversation(entries: initialEntries)
        let initialRevision = model.transcriptRevisionsByThreadID[threadID]
        XCTAssertEqual(model.transcriptPresentationCache.count, 1)

        model.appendEntry(
            .actionCard(action(threadID: threadID, method: "turn/completed", title: "Turn completed")),
            to: threadID
        )

        guard case let .loaded(updatedEntries) = model.conversationState else {
            XCTFail("Expected loaded conversation state")
            return
        }
        let updatedRows = model.presentationRowsForSelectedConversation(entries: updatedEntries)

        XCTAssertEqual(model.transcriptPresentationCache.count, 1)
        XCTAssertEqual(model.transcriptRevisionsByThreadID[threadID], (initialRevision ?? 0) + 1)
        XCTAssertGreaterThan(updatedRows.count, 1)
    }

    @MainActor
    func testDetailLevelSwitchUsesDifferentCacheKey() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let threadID = UUID()
        model.selectedThreadID = threadID
        model.transcriptStore[threadID] = [
            .message(userMessage(threadID: threadID, text: "Ship release")),
            .actionCard(action(threadID: threadID, method: "turn/completed", title: "Turn completed")),
        ]
        model.bumpTranscriptRevision(for: threadID)
        model.refreshConversationState()

        guard case let .loaded(entries) = model.conversationState else {
            XCTFail("Expected loaded conversation state")
            return
        }

        model.transcriptDetailLevel = .chat
        let chatRows = model.presentationRowsForSelectedConversation(entries: entries)

        model.transcriptDetailLevel = .detailed
        let detailedRows = model.presentationRowsForSelectedConversation(entries: entries)

        XCTAssertNotEqual(chatRows, detailedRows)
        XCTAssertEqual(model.transcriptPresentationCache.count, 2)
    }

    private func userMessage(threadID: UUID, text: String) -> ChatMessage {
        ChatMessage(threadId: threadID, role: .user, text: text)
    }

    private func action(
        threadID: UUID,
        method: String,
        title: String,
        detail: String = "detail"
    ) -> ActionCard {
        ActionCard(
            threadID: threadID,
            method: method,
            title: title,
            detail: detail
        )
    }
}

private extension [TranscriptPresentationRow] {
    var messageCount: Int {
        count {
            if case .message = $0 { return true }
            return false
        }
    }

    var turnSummaryCount: Int {
        count {
            if case .turnSummary = $0 { return true }
            return false
        }
    }

    var actionMethods: [String] {
        compactMap {
            guard case let .action(action) = $0 else {
                return nil
            }
            return action.method
        }
    }
}
