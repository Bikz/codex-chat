import CodexChatInfra
@testable import CodexChatShared
import CodexKit
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
        let runtime = CodexRuntime(executableResolver: { nil })
        let model = AppModel(
            repositories: repositories,
            runtime: runtime,
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

    func testManualChatGPTSignInIsHiddenWhenSharedAuthExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-shared-auth-signin-hidden-\(UUID().uuidString)", isDirectory: true)
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

        XCTAssertFalse(model.shouldOfferManualChatGPTSignIn)
    }

    func testAutomaticSharedAuthRefreshTriggersOnlyForConnectedSignedOutState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-shared-auth-refresh-decision-\(UUID().uuidString)", isDirectory: true)
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
        XCTAssertTrue(model.shouldAttemptAutomaticSharedAuthRefresh(after: .signedOut, refreshToken: false))

        model.hasAttemptedAutomaticSharedAuthRefresh = true
        XCTAssertFalse(model.shouldAttemptAutomaticSharedAuthRefresh(after: .signedOut, refreshToken: false))
    }

    func testAutomaticSharedAuthRuntimeRecoveryRequiresRecoverableRuntimeFailure() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexchat-shared-auth-runtime-recovery-\(UUID().uuidString)", isDirectory: true)
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
        let modelWithoutRuntime = AppModel(
            repositories: repositories,
            runtime: nil,
            bootError: nil,
            storagePaths: storagePaths,
            resolvedCodexHomes: resolvedCodexHomes
        )

        modelWithoutRuntime.runtimeStatus = .error
        modelWithoutRuntime.runtimeIssue = .recoverable("Runtime unavailable")
        XCTAssertFalse(modelWithoutRuntime.shouldAttemptAutomaticSharedAuthRuntimeRecovery())

        let runtime = CodexRuntime(executableResolver: { nil })
        let modelWithRuntime = AppModel(
            repositories: repositories,
            runtime: runtime,
            bootError: nil,
            storagePaths: storagePaths,
            resolvedCodexHomes: resolvedCodexHomes
        )

        modelWithRuntime.runtimeStatus = .error
        modelWithRuntime.runtimeIssue = .recoverable("Runtime unavailable")
        XCTAssertTrue(modelWithRuntime.shouldAttemptAutomaticSharedAuthRuntimeRecovery())

        modelWithRuntime.didAttemptSharedAuthRuntimeRecovery = true
        XCTAssertFalse(modelWithRuntime.shouldAttemptAutomaticSharedAuthRuntimeRecovery())
    }
}
