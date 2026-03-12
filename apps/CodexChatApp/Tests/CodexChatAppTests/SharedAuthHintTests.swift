import CodexChatInfra
@testable import CodexChatShared
import Foundation
import XCTest

@MainActor
final class SharedAuthHintTests: XCTestCase {
    func testSharedAuthHintAppearsWhenRuntimeIsUnavailableButSharedAuthExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-shared-auth-hint-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storagePaths = CodexChatStoragePaths(rootURL: root)
        try storagePaths.ensureRootStructure()
        let resolvedCodexHomes = makeTestResolvedCodexHomes(root: root, storagePaths: storagePaths)
        try FileManager.default.createDirectory(at: resolvedCodexHomes.activeCodexHomeURL, withIntermediateDirectories: true)
        try """
        {
          "chatgpt": {
            "refresh_token": "shared-refresh-token"
          }
        }
        """.write(
            to: resolvedCodexHomes.activeCodexHomeURL.appendingPathComponent("auth.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let database = try MetadataDatabase(databaseURL: storagePaths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths,
            resolvedCodexHomes: resolvedCodexHomes
        )
        model.runtimeStatus = .error
        model.runtimeIssue = .recoverable("Runtime unavailable")

        let hint = try XCTUnwrap(model.sharedAuthDetectionHint)
        XCTAssertTrue(hint.contains(resolvedCodexHomes.activeCodexHomeURL.path))
        XCTAssertTrue(hint.contains("Detected shared Codex login"))
    }

    func testSharedAuthHintStaysHiddenWhenRuntimeIsConnectedAndSignedOut() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-shared-auth-hint-hidden-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storagePaths = CodexChatStoragePaths(rootURL: root)
        try storagePaths.ensureRootStructure()
        let resolvedCodexHomes = makeTestResolvedCodexHomes(root: root, storagePaths: storagePaths)
        try FileManager.default.createDirectory(at: resolvedCodexHomes.activeCodexHomeURL, withIntermediateDirectories: true)
        try """
        {
          "chatgpt": {
            "refresh_token": "shared-refresh-token"
          }
        }
        """.write(
            to: resolvedCodexHomes.activeCodexHomeURL.appendingPathComponent("auth.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let database = try MetadataDatabase(databaseURL: storagePaths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let model = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths,
            resolvedCodexHomes: resolvedCodexHomes
        )
        model.runtimeStatus = .connected
        model.runtimeIssue = nil

        XCTAssertNil(model.sharedAuthDetectionHint)
    }
}
