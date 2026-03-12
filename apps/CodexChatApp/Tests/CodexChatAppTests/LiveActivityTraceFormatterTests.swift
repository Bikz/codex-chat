import CodexChatCore
@testable import CodexChatShared
import XCTest

final class LiveActivityTraceFormatterTests: XCTestCase {
    func testGenericLifecycleActionsUseCompactSingleLineStatus() {
        let threadID = UUID()
        let actions = [
            action(threadID: threadID, method: "item/started", title: "Started reasoning"),
            action(threadID: threadID, method: "item/completed", title: "Completed reasoning"),
            action(threadID: threadID, method: "item/started", title: "Started webSearch"),
        ]

        let presentation = LiveActivityTraceFormatter.buildPresentation(
            actions: actions,
            fallbackTitle: "Started webSearch",
            detailLevel: .chat
        )

        XCTAssertEqual(presentation.statusLabel, "Searching")
        XCTAssertFalse(presentation.showTraceBox)
        XCTAssertTrue(presentation.lines.isEmpty)
    }

    func testRichCommandTraceShowsTraceBoxAndFiltersGenericLifecycleRows() {
        let threadID = UUID()
        let actions = [
            action(threadID: threadID, method: "item/started", title: "Started reasoning"),
            action(
                threadID: threadID,
                method: "item/completed",
                title: "Completed commandExecution",
                detail: "npm run build completed in 1.2s"
            ),
        ]

        let presentation = LiveActivityTraceFormatter.buildPresentation(
            actions: actions,
            fallbackTitle: "Completed commandExecution",
            detailLevel: .chat
        )

        XCTAssertEqual(presentation.statusLabel, "Running")
        XCTAssertTrue(presentation.showTraceBox)
        XCTAssertEqual(presentation.lines.count, 1)
        XCTAssertEqual(presentation.lines[0].text, "Command complete")
    }

    func testDetailedModeAlwaysShowsTraceBox() {
        let threadID = UUID()
        let actions = [
            action(threadID: threadID, method: "item/started", title: "Started reasoning"),
            action(threadID: threadID, method: "item/completed", title: "Completed reasoning"),
        ]

        let presentation = LiveActivityTraceFormatter.buildPresentation(
            actions: actions,
            fallbackTitle: "Started reasoning",
            detailLevel: .detailed
        )

        XCTAssertTrue(presentation.showTraceBox)
        XCTAssertEqual(presentation.lines.count, 2)
        XCTAssertEqual(
            presentation.lines.map(\.text),
            ["Thinking through the response", "Reasoning complete"]
        )
    }

    func testErrorStatusMapsToTroubleshooting() {
        let threadID = UUID()
        let actions = [
            action(
                threadID: threadID,
                method: "runtime/stderr",
                title: "Runtime stderr",
                detail: "fatal: segmentation fault"
            ),
        ]

        let presentation = LiveActivityTraceFormatter.buildPresentation(
            actions: actions,
            fallbackTitle: "Runtime stderr",
            detailLevel: .chat
        )

        XCTAssertEqual(presentation.statusLabel, "Troubleshooting")
        XCTAssertTrue(presentation.showTraceBox)
        XCTAssertEqual(presentation.lines.count, 1)
    }

    func testDecodeErrorActionIsSuppressedFromLiveTrace() {
        let threadID = UUID()
        let actions = [
            action(
                threadID: threadID,
                method: "runtime/stdout/decode_error",
                title: "Runtime stream decode error",
                detail: "The data couldn't be read because it isn't in the correct format."
            ),
        ]

        let presentation = LiveActivityTraceFormatter.buildPresentation(
            actions: actions,
            fallbackTitle: "Runtime stream decode error",
            detailLevel: .chat
        )

        XCTAssertFalse(presentation.showTraceBox)
        XCTAssertTrue(presentation.lines.isEmpty)
    }

    func testDecodeErrorSuppressionKeepsVisibleActionAsStatusSource() {
        let threadID = UUID()
        let actions = [
            action(
                threadID: threadID,
                method: "runtime/stdout/decode_error",
                title: "Runtime stream decode error",
                detail: "The data couldn't be read because it isn't in the correct format."
            ),
            action(threadID: threadID, method: "item/started", title: "Started reasoning"),
        ]

        let presentation = LiveActivityTraceFormatter.buildPresentation(
            actions: actions,
            fallbackTitle: "Runtime stream decode error",
            detailLevel: .chat
        )

        XCTAssertEqual(presentation.statusLabel, "Thinking")
        XCTAssertFalse(presentation.showTraceBox)
        XCTAssertTrue(presentation.lines.isEmpty)
    }

    func testPlanUpdateAndModelRerouteUseHumanReadableStates() {
        let threadID = UUID()
        let actions = [
            action(threadID: threadID, method: "turn/plan/updated", title: "Plan updated", detail: "Review auth flow"),
            action(threadID: threadID, method: "model/rerouted", title: "Model rerouted", detail: "gpt-5 -> gpt-5.2"),
        ]

        let planPresentation = LiveActivityTraceFormatter.buildPresentation(
            actions: [actions[0]],
            fallbackTitle: "Plan updated",
            detailLevel: .chat
        )
        XCTAssertEqual(planPresentation.statusLabel, "Updating plan")

        let reroutePresentation = LiveActivityTraceFormatter.buildPresentation(
            actions: actions,
            fallbackTitle: "Model rerouted",
            detailLevel: .chat
        )
        XCTAssertEqual(reroutePresentation.statusLabel, "Switching model")
        XCTAssertTrue(reroutePresentation.showTraceBox)
    }

    private func action(
        threadID: UUID,
        method: String,
        title: String,
        detail: String = ""
    ) -> ActionCard {
        ActionCard(
            threadID: threadID,
            method: method,
            title: title,
            detail: detail,
            createdAt: Date()
        )
    }
}
