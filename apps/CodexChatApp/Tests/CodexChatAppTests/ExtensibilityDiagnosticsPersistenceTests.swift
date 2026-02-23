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
