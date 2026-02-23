import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import XCTest

@MainActor
final class ExtensionAutomationHealthTests: XCTestCase {
    func testSummarizeAutomationHealthAggregatesFailuresAndScheduling() {
        let now = Date()
        let records: [ExtensionAutomationStateRecord] = [
            .init(
                modID: "acme.mod",
                automationID: "daily-sync",
                nextRunAt: now.addingTimeInterval(600),
                lastRunAt: now.addingTimeInterval(-300),
                lastStatus: "ok",
                lastError: nil
            ),
            .init(
                modID: "acme.mod",
                automationID: "hourly-report",
                nextRunAt: now.addingTimeInterval(120),
                lastRunAt: now.addingTimeInterval(-60),
                lastStatus: "failed",
                lastError: "network timeout"
            ),
        ]

        let summary = AppModel.summarizeAutomationHealth(
            modID: "acme.mod",
            records: records
        )

        XCTAssertEqual(summary?.modID, "acme.mod")
        XCTAssertEqual(summary?.automationCount, 2)
        XCTAssertEqual(summary?.failingAutomationCount, 1)
        XCTAssertEqual(summary?.lastStatus, "failed")
        XCTAssertEqual(summary?.lastError, "network timeout")
        XCTAssertEqual(summary?.nextRunAt, now.addingTimeInterval(120))
    }

    func testRefreshAutomationHealthSummariesLoadsRepositoryState() async throws {
        let repositories = try makeRepositories(prefix: "automation-health")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        _ = try await repositories.extensionAutomationStateRepository.upsert(
            ExtensionAutomationStateRecord(
                modID: "acme.mod",
                automationID: "daily-sync",
                nextRunAt: Date().addingTimeInterval(300),
                lastRunAt: Date().addingTimeInterval(-30),
                lastStatus: "scheduled",
                lastError: nil
            )
        )

        await model.refreshAutomationHealthSummaries(for: ["acme.mod"])
        let summary = model.extensionAutomationHealthByModID["acme.mod"]

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.automationCount, 1)
        XCTAssertEqual(summary?.failingAutomationCount, 0)
        XCTAssertEqual(summary?.lastStatus, "scheduled")
    }

    func testRefreshAutomationHealthSummariesClearsStateForEmptyModSet() async {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.extensionAutomationHealthByModID = [
            "acme.mod": .init(
                modID: "acme.mod",
                automationCount: 1,
                failingAutomationCount: 0,
                nextRunAt: nil,
                lastRunAt: nil,
                lastStatus: "ok",
                lastError: nil
            ),
        ]

        await model.refreshAutomationHealthSummaries(for: [])

        XCTAssertTrue(model.extensionAutomationHealthByModID.isEmpty)
    }

    private func makeRepositories(prefix: String) throws -> MetadataRepositories {
        let root = try makeTempDirectory(prefix: prefix)
        let database = try MetadataDatabase(
            databaseURL: root.appendingPathComponent("metadata.sqlite", isDirectory: false)
        )
        return MetadataRepositories(database: database)
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
