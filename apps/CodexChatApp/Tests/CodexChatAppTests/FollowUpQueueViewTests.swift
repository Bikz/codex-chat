import CodexChatCore
@testable import CodexChatShared
import XCTest

@MainActor
final class FollowUpQueueViewTests: XCTestCase {
    func testCompactTitleUsesContinueForUserQueuedItems() {
        let item = FollowUpQueueItemRecord(
            threadID: UUID(),
            source: .userQueued,
            dispatchMode: .auto,
            text: "tell me a joke",
            sortIndex: 0
        )

        XCTAssertEqual(FollowUpQueueView.compactTitle(for: item), "Continue")
        XCTAssertFalse(FollowUpQueueView.shouldShowVerboseText(for: item))
    }

    func testCompactTitleKeepsAssistantSuggestionText() {
        let item = FollowUpQueueItemRecord(
            threadID: UUID(),
            source: .assistantSuggestion,
            dispatchMode: .manual,
            text: "Review changes",
            sortIndex: 0
        )

        XCTAssertEqual(FollowUpQueueView.compactTitle(for: item), "Review changes")
        XCTAssertTrue(FollowUpQueueView.shouldShowVerboseText(for: item))
    }

    func testPlanSummaryRequiresActivePlanForSelectedThread() {
        let selectedThreadID = UUID()
        let otherThreadID = UUID()
        let activePlanRun = PlanRunRecord(
            threadID: otherThreadID,
            projectID: UUID(),
            title: "Patch hosted shell",
            status: .running,
            totalTasks: 3,
            completedTasks: 1
        )

        XCTAssertNil(
            FollowUpQueueView.planSummary(
                activePlanRun: activePlanRun,
                taskStates: [],
                selectedThreadID: selectedThreadID
            )
        )
    }

    func testPlanSummaryBuildsCompactProgressAndTasks() {
        let selectedThreadID = UUID()
        let planRun = PlanRunRecord(
            threadID: selectedThreadID,
            projectID: UUID(),
            title: "Production patch",
            status: .running,
            totalTasks: 4,
            completedTasks: 1
        )
        let tasks = [
            PlanRunTaskRecord(planRunID: planRun.id, taskID: "1", title: "Patch builders", status: .completed),
            PlanRunTaskRecord(planRunID: planRun.id, taskID: "2", title: "Add tests", status: .running),
            PlanRunTaskRecord(planRunID: planRun.id, taskID: "3", title: "Deploy", status: .pending),
            PlanRunTaskRecord(planRunID: planRun.id, taskID: "4", title: "Verify", status: .pending),
        ]

        let summary = FollowUpQueueView.planSummary(
            activePlanRun: planRun,
            taskStates: tasks,
            selectedThreadID: selectedThreadID
        )

        XCTAssertEqual(summary?.title, "Production patch")
        XCTAssertEqual(summary?.subtitle, "1 of 4 tasks completed")
        XCTAssertEqual(summary?.visibleTasks.map(\.title), ["Patch builders", "Add tests", "Deploy"])
        XCTAssertEqual(summary?.hasOverflowTasks, true)
    }
}
