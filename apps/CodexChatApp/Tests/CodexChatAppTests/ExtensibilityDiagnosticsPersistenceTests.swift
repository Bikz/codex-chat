import CodexChatCore
import CodexChatInfra
@testable import CodexChatShared
import XCTest

@MainActor
final class ExtensibilityDiagnosticsPersistenceTests: XCTestCase {
    func testPersistAndRestoreExtensibilityDiagnostics() async throws {
        let repositories = try makeRepositories(prefix: "ext-diagnostics-persist")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        let details = AppModel.ExtensibilityProcessFailureDetails(
            kind: .timeout,
            command: "git pull --ff-only",
            summary: "Timed out after 100ms."
        )
        model.recordExtensibilityDiagnostic(surface: "skills", operation: "install", details: details)
        await model.persistExtensibilityDiagnosticsIfNeeded()

        let restored = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        await restored.restoreExtensibilityDiagnosticsIfNeeded()

        XCTAssertEqual(restored.extensibilityDiagnostics.count, 1)
        XCTAssertEqual(restored.extensibilityDiagnostics.first?.surface, "skills")
        XCTAssertEqual(restored.extensibilityDiagnostics.first?.operation, "install")
        XCTAssertEqual(restored.extensibilityDiagnostics.first?.kind, "timeout")
    }

    func testRestoreClearsDiagnosticsWhenPreferenceRepositoryUnavailable() async {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.extensibilityDiagnostics = [
            .init(surface: "mods", operation: "update", kind: "command", command: "git", summary: "failed"),
        ]

        await model.restoreExtensibilityDiagnosticsIfNeeded()

        XCTAssertTrue(model.extensibilityDiagnostics.isEmpty)
    }

    func testPersistAndRestoreRetentionLimit() async throws {
        let repositories = try makeRepositories(prefix: "ext-diagnostics-retention")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        model.setExtensibilityDiagnosticsRetentionLimit(175)
        await model.persistExtensibilityDiagnosticsRetentionLimitIfNeeded()

        let restored = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        await restored.restoreExtensibilityDiagnosticsRetentionLimitIfNeeded()

        XCTAssertEqual(restored.extensibilityDiagnosticsRetentionLimit, 175)
    }

    func testRetentionLimitIsClamped() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.setExtensibilityDiagnosticsRetentionLimit(1)
        XCTAssertEqual(model.extensibilityDiagnosticsRetentionLimit, 25)

        model.setExtensibilityDiagnosticsRetentionLimit(5000)
        XCTAssertEqual(model.extensibilityDiagnosticsRetentionLimit, 500)
    }

    func testPersistAndRestoreAutomationTimelineFocusFilter() async throws {
        let repositories = try makeRepositories(prefix: "ext-diagnostics-focus-filter")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        model.setAutomationTimelineFocusFilter(.selectedProject)

        let deadline = Date().addingTimeInterval(3)
        var persisted: String?
        repeat {
            persisted = try await repositories.preferenceRepository.getPreference(
                key: .extensibilityAutomationTimelineFocusFilterV1
            )
            if persisted == AppModel.AutomationTimelineFocusFilter.selectedProject.rawValue {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        } while Date() < deadline

        XCTAssertEqual(persisted, AppModel.AutomationTimelineFocusFilter.selectedProject.rawValue)

        let restored = AppModel(repositories: repositories, runtime: nil, bootError: nil)
        await restored.restoreAutomationTimelineFocusFilterIfNeeded()
        XCTAssertEqual(restored.automationTimelineFocusFilter, .selectedProject)
    }

    func testAutomationTimelineFocusPersistenceWaitsForInFlightPersistenceTask() async throws {
        let repositories = try makeRepositories(prefix: "ext-diagnostics-focus-filter-ordering")
        let model = AppModel(repositories: repositories, runtime: nil, bootError: nil)

        model.automationTimelineFocusFilterPersistenceTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
        }

        model.setAutomationTimelineFocusFilter(.selectedProject)

        try await Task.sleep(nanoseconds: 120_000_000)
        let pendingValue = try await repositories.preferenceRepository.getPreference(
            key: .extensibilityAutomationTimelineFocusFilterV1
        )
        XCTAssertNil(pendingValue)

        if let task = model.automationTimelineFocusFilterPersistenceTask {
            _ = await task.result
        }

        let persisted = try await repositories.preferenceRepository.getPreference(
            key: .extensibilityAutomationTimelineFocusFilterV1
        )
        XCTAssertEqual(persisted, AppModel.AutomationTimelineFocusFilter.selectedProject.rawValue)
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
