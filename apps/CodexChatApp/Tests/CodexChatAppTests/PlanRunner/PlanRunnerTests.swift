@testable import CodexChatShared
import XCTest

final class PlanRunnerTests: XCTestCase {
    func testParserExtractsTasksDependenciesAndPhases() throws {
        let text = """
        # Phase 1
        - Task 1.0 Define scope
        - Task 1.1 Parse plan (depends on: 1.0)
        - Task 1.2 Build scheduler
          Dependencies: 1.1

        # Phase 2
        - Task 2.1 Wire UI
          - depends on: 1.2
        """

        let document = try PlanParser.parse(text)

        XCTAssertEqual(document.tasks.count, 4)
        XCTAssertEqual(document.taskByID["1.0"]?.phaseTitle, "Phase 1")
        XCTAssertEqual(document.taskByID["1.2"]?.dependencies, ["1.1"])
        XCTAssertEqual(document.taskByID["2.1"]?.dependencies, ["1.2"])
    }

    func testParserRejectsUnknownDependencies() {
        let text = """
        - Task 1.0 Define scope
        - Task 1.1 Implement feature
          Dependencies: 9.9
        """

        XCTAssertThrowsError(try PlanParser.parse(text)) { error in
            guard case let PlanParserError.unknownDependency(taskID, dependencyID) = error else {
                XCTFail("Expected unknownDependency error, got \(error)")
                return
            }
            XCTAssertEqual(taskID, "1.1")
            XCTAssertEqual(dependencyID, "9.9")
        }
    }

    func testSchedulerComputesUnblockedBatches() throws {
        let text = """
        - Task 1.0 Define scope
        - Task 1.1 Parse plan
          Dependencies: 1.0
        - Task 1.2 Build scheduler
          Dependencies: 1.0
        """

        let document = try PlanParser.parse(text)
        let scheduler = try PlanScheduler(document: document)

        var state = PlanExecutionState()
        XCTAssertEqual(
            scheduler.nextUnblockedBatch(state: state, preferredBatchSize: 8, multiAgentEnabled: true)
                .map(\.id),
            ["1.0"]
        )

        state.completedTaskIDs.insert("1.0")
        XCTAssertEqual(
            scheduler.nextUnblockedBatch(state: state, preferredBatchSize: 8, multiAgentEnabled: true)
                .map(\.id),
            ["1.1", "1.2"]
        )
    }

    func testSchedulerFallsBackToSequentialWhenMultiAgentDisabled() throws {
        let text = """
        - Task 1.0 Define scope
        - Task 1.1 Parse plan
          Dependencies: 1.0
        - Task 1.2 Build scheduler
          Dependencies: 1.0
        """

        let document = try PlanParser.parse(text)
        let scheduler = try PlanScheduler(document: document)

        let state = PlanExecutionState(completedTaskIDs: ["1.0"])
        XCTAssertEqual(
            scheduler.nextUnblockedBatch(state: state, preferredBatchSize: 8, multiAgentEnabled: false)
                .map(\.id),
            ["1.1"]
        )
    }

    func testSchedulerDetectsCycle() throws {
        let tasks: [PlanTask] = [
            PlanTask(id: "1.0", title: "A", phaseTitle: nil, dependencies: ["1.1"], lineNumber: 1),
            PlanTask(id: "1.1", title: "B", phaseTitle: nil, dependencies: ["1.0"], lineNumber: 2),
        ]

        XCTAssertThrowsError(try PlanScheduler(document: PlanDocument(tasks: tasks))) { error in
            guard case let PlanSchedulerError.cycleDetected(taskIDs) = error else {
                XCTFail("Expected cycleDetected error, got \(error)")
                return
            }
            XCTAssertEqual(taskIDs, ["1.0", "1.1"])
        }
    }
}
