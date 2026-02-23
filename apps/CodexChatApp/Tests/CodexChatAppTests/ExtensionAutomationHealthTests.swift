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
            .init(
                modID: "acme.mod",
                automationID: "nightly-cleanup",
                nextRunAt: now.addingTimeInterval(900),
                lastRunAt: now.addingTimeInterval(-120),
                lastStatus: "launchd-scheduled",
                lastError: nil
            ),
        ]

        let summary = AppModel.summarizeAutomationHealth(
            modID: "acme.mod",
            records: records
        )

        XCTAssertEqual(summary?.modID, "acme.mod")
        XCTAssertEqual(summary?.automationCount, 3)
        XCTAssertEqual(summary?.failingAutomationCount, 1)
        XCTAssertEqual(summary?.launchdScheduledAutomationCount, 1)
        XCTAssertEqual(summary?.launchdFailingAutomationCount, 0)
        XCTAssertEqual(summary?.lastStatus, "failed")
        XCTAssertEqual(summary?.lastError, "network timeout")
        XCTAssertEqual(summary?.nextRunAt, now.addingTimeInterval(120))
    }

    func testSummarizeAutomationHealthTracksLaunchdFailuresSeparately() {
        let now = Date()
        let records: [ExtensionAutomationStateRecord] = [
            .init(
                modID: "acme.mod",
                automationID: "nightly-cleanup",
                nextRunAt: nil,
                lastRunAt: now.addingTimeInterval(-30),
                lastStatus: "launchd-failed",
                lastError: "bootstrap failed"
            ),
        ]

        let summary = AppModel.summarizeAutomationHealth(
            modID: "acme.mod",
            records: records
        )

        XCTAssertEqual(summary?.failingAutomationCount, 1)
        XCTAssertEqual(summary?.launchdFailingAutomationCount, 1)
        XCTAssertTrue(summary?.hasLaunchdFailures == true)
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
                lastStatus: "launchd-scheduled",
                lastError: nil
            )
        )

        await model.refreshAutomationHealthSummaries(for: ["acme.mod"])
        let summary = model.extensionAutomationHealthByModID["acme.mod"]

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.automationCount, 1)
        XCTAssertEqual(summary?.failingAutomationCount, 0)
        XCTAssertEqual(summary?.launchdScheduledAutomationCount, 1)
        XCTAssertEqual(summary?.lastStatus, "launchd-scheduled")
    }

    func testRefreshAutomationHealthSummariesClearsStateForEmptyModSet() async {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.extensionAutomationHealthByModID = [
            "acme.mod": .init(
                modID: "acme.mod",
                automationCount: 1,
                failingAutomationCount: 0,
                launchdScheduledAutomationCount: 0,
                launchdFailingAutomationCount: 0,
                nextRunAt: nil,
                lastRunAt: nil,
                lastStatus: "ok",
                lastError: nil
            ),
        ]

        await model.refreshAutomationHealthSummaries(for: [])

        XCTAssertTrue(model.extensionAutomationHealthByModID.isEmpty)
    }

    func testRefreshAutomationHealthSummaryRecordsDiagnosticsOnFailingTransition() async throws {
        let repositories = try makeRepositories(prefix: "automation-health-diag")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        _ = try await repositories.extensionAutomationStateRepository.upsert(
            ExtensionAutomationStateRecord(
                modID: "acme.mod",
                automationID: "daily-sync",
                nextRunAt: nil,
                lastRunAt: Date(),
                lastStatus: "failed",
                lastError: "network timeout"
            )
        )

        await model.refreshAutomationHealthSummary(for: "acme.mod")

        XCTAssertEqual(model.extensibilityDiagnostics.first?.surface, "automations")
        XCTAssertEqual(model.extensibilityDiagnostics.first?.operation, "health")
        XCTAssertEqual(model.extensibilityDiagnostics.first?.kind, "command")
        XCTAssertTrue(model.extensibilityDiagnostics.first?.summary.contains("acme.mod") == true)
    }

    func testRefreshAutomationHealthSummaryDoesNotDuplicateUnchangedFailingDiagnostics() async throws {
        let repositories = try makeRepositories(prefix: "automation-health-dedup")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        _ = try await repositories.extensionAutomationStateRepository.upsert(
            ExtensionAutomationStateRecord(
                modID: "acme.mod",
                automationID: "daily-sync",
                nextRunAt: nil,
                lastRunAt: Date(),
                lastStatus: "failed",
                lastError: "network timeout"
            )
        )

        await model.refreshAutomationHealthSummary(for: "acme.mod")
        let firstCount = model.extensibilityDiagnostics.count
        await model.refreshAutomationHealthSummary(for: "acme.mod")

        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(model.extensibilityDiagnostics.count, 1)
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
