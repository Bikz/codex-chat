@testable import CodexChatShared
import Foundation
import XCTest

final class CodexStorageMigrationCoordinatorTests: XCTestCase {
    private let runtimeDirectoryNames = [
        "sessions",
        "archived_sessions",
        "shell_snapshots",
        "sqlite",
        "log",
        "tmp",
        "vendor_imports",
        "worktrees",
    ]

    private let runtimeFileNames = [
        ".codex-global-state.json",
        "models_cache.json",
        ".personality_migration",
        "version.json",
    ]

    func testPerformInitialMigrationImportsOnlySelectedArtifactsAndDoesNotOverwrite() throws {
        let fileManager = FileManager.default
        let root = tempDirectory(prefix: "codexchat-storage-migrate-selective")
        defer { try? fileManager.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure(fileManager: fileManager)

        let legacyCodexHome = root.appendingPathComponent("legacy-codex-home", isDirectory: true)
        let legacyAgentsHome = root.appendingPathComponent("legacy-agents-home", isDirectory: true)
        try fileManager.createDirectory(at: legacyCodexHome, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: legacyAgentsHome, withIntermediateDirectories: true)

        try write("existing-config", to: paths.codexHomeURL.appendingPathComponent("config.toml"))

        try write("from-source-config", to: legacyCodexHome.appendingPathComponent("config.toml"))
        try write("auth", to: legacyCodexHome.appendingPathComponent("auth.json"))
        try write("history", to: legacyCodexHome.appendingPathComponent("history.jsonl"))
        try write("credentials", to: legacyCodexHome.appendingPathComponent(".credentials.json"))
        try write("agents-global", to: legacyCodexHome.appendingPathComponent("AGENTS.md"))
        try write("agents-override", to: legacyCodexHome.appendingPathComponent("AGENTS.override.md"))
        try write("memory", to: legacyCodexHome.appendingPathComponent("memory.md"))

        let codexSkill = legacyCodexHome
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("codex-skill", isDirectory: true)
            .appendingPathComponent("SKILL.md", isDirectory: false)
        try write("codex skill", to: codexSkill)

        let sessionsDir = legacyCodexHome.appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try write("rollout", to: sessionsDir.appendingPathComponent("rollout-1.jsonl"))

        let legacyAgentSkill = legacyAgentsHome
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("agent-skill", isDirectory: true)
            .appendingPathComponent("SKILL.md", isDirectory: false)
        try write("agent skill", to: legacyAgentSkill)

        try CodexChatStorageMigrationCoordinator.performInitialMigrationIfNeeded(
            paths: paths,
            fileManager: fileManager,
            legacyCodexHomeURL: legacyCodexHome,
            legacyAgentsHomeURL: legacyAgentsHome
        )

        let config = try String(contentsOf: paths.codexHomeURL.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertEqual(config, "existing-config")
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("auth.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("history.jsonl").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent(".credentials.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("AGENTS.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("AGENTS.override.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("memory.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("skills/codex-skill/SKILL.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.agentsHomeURL.appendingPathComponent("skills/agent-skill/SKILL.md").path))

        XCTAssertFalse(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("sessions").path))
        XCTAssertFalse(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("rollout-1.jsonl").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.migrationMarkerURL.path))
    }

    func testNormalizeManagedCodexHomeQuarantinesRuntimeStateAndPreservesUserArtifacts() throws {
        let fileManager = FileManager.default
        let root = tempDirectory(prefix: "codexchat-storage-normalize")
        defer { try? fileManager.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure(fileManager: fileManager)

        try write("config", to: paths.codexHomeURL.appendingPathComponent("config.toml"))
        try write("auth", to: paths.codexHomeURL.appendingPathComponent("auth.json"))
        try write("history", to: paths.codexHomeURL.appendingPathComponent("history.jsonl"))
        try write("global-agent", to: paths.codexHomeURL.appendingPathComponent("AGENTS.md"))
        try write("memory", to: paths.codexHomeURL.appendingPathComponent("memory.md"))
        try write("skill", to: paths.codexHomeURL.appendingPathComponent("skills/my-skill/SKILL.md"))

        for directoryName in runtimeDirectoryNames {
            try write(
                "runtime",
                to: paths.codexHomeURL
                    .appendingPathComponent(directoryName, isDirectory: true)
                    .appendingPathComponent("item.txt", isDirectory: false)
            )
        }
        for fileName in runtimeFileNames {
            try write("runtime-file", to: paths.codexHomeURL.appendingPathComponent(fileName, isDirectory: false))
        }

        let result = try CodexChatStorageMigrationCoordinator.normalizeManagedCodexHome(
            paths: paths,
            force: false,
            reason: "startup-test",
            fileManager: fileManager
        )

        XCTAssertTrue(result.executed)
        XCTAssertGreaterThan(result.movedItemCount, 0)
        XCTAssertNotNil(result.quarantineURL)
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeNormalizationMarkerURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeLastRepairReportURL.path))

        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("config.toml").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("auth.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("history.jsonl").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("AGENTS.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("memory.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("skills/my-skill/SKILL.md").path))

        for directoryName in runtimeDirectoryNames {
            XCTAssertFalse(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent(directoryName).path))
        }
        for fileName in runtimeFileNames {
            XCTAssertFalse(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent(fileName).path))
        }

        let report = try XCTUnwrap(
            CodexChatStorageMigrationCoordinator.readLastCodexHomeNormalizationReport(paths: paths, fileManager: fileManager)
        )
        XCTAssertEqual(report.reason, "startup-test")
        XCTAssertEqual(report.forced, false)
        XCTAssertEqual(report.codexHomePath, paths.codexHomeURL.path)
        XCTAssertNotNil(report.quarantinePath)
    }

    func testForcedNormalizationRunsEvenWhenMarkerExists() throws {
        let fileManager = FileManager.default
        let root = tempDirectory(prefix: "codexchat-storage-force")
        defer { try? fileManager.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure(fileManager: fileManager)

        try write(
            "runtime",
            to: paths.codexHomeURL
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent("a.jsonl", isDirectory: false)
        )

        _ = try CodexChatStorageMigrationCoordinator.normalizeManagedCodexHome(
            paths: paths,
            force: false,
            reason: "first-pass",
            fileManager: fileManager
        )

        try write(
            "runtime",
            to: paths.codexHomeURL
                .appendingPathComponent("log", isDirectory: true)
                .appendingPathComponent("stderr.log", isDirectory: false)
        )

        let skipped = try CodexChatStorageMigrationCoordinator.normalizeManagedCodexHome(
            paths: paths,
            force: false,
            reason: "second-pass",
            fileManager: fileManager
        )

        XCTAssertFalse(skipped.executed)
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("log").path))

        let forced = try CodexChatStorageMigrationCoordinator.normalizeManagedCodexHome(
            paths: paths,
            force: true,
            reason: "manual-repair",
            fileManager: fileManager
        )

        XCTAssertTrue(forced.executed)
        XCTAssertTrue(forced.forced)
        XCTAssertTrue(forced.movedEntries.contains("log"))
        XCTAssertFalse(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("log").path))
    }

    func testNormalizeManagedCodexHomeNoOpWhenHealthy() throws {
        let fileManager = FileManager.default
        let root = tempDirectory(prefix: "codexchat-storage-healthy")
        defer { try? fileManager.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure(fileManager: fileManager)

        try write("config", to: paths.codexHomeURL.appendingPathComponent("config.toml"))
        try write("auth", to: paths.codexHomeURL.appendingPathComponent("auth.json"))
        try write("history", to: paths.codexHomeURL.appendingPathComponent("history.jsonl"))
        try write("skill", to: paths.codexHomeURL.appendingPathComponent("skills/ok/SKILL.md"))

        let first = try CodexChatStorageMigrationCoordinator.normalizeManagedCodexHome(
            paths: paths,
            force: false,
            reason: "startup",
            fileManager: fileManager
        )

        XCTAssertTrue(first.executed)
        XCTAssertEqual(first.movedItemCount, 0)
        XCTAssertNil(first.quarantineURL)

        let second = try CodexChatStorageMigrationCoordinator.normalizeManagedCodexHome(
            paths: paths,
            force: false,
            reason: "startup",
            fileManager: fileManager
        )

        XCTAssertFalse(second.executed)
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("config.toml").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.codexHomeURL.appendingPathComponent("skills/ok/SKILL.md").path))
    }

    func testNormalizeManagedCodexHomeDoesNotThrowWhenLastReportIsCorrupted() throws {
        let fileManager = FileManager.default
        let root = tempDirectory(prefix: "codexchat-storage-corrupt-report")
        defer { try? fileManager.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure(fileManager: fileManager)

        try "version=1\n".write(
            to: paths.codexHomeNormalizationMarkerURL,
            atomically: true,
            encoding: .utf8
        )
        try "{not-json".write(
            to: paths.codexHomeLastRepairReportURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try CodexChatStorageMigrationCoordinator.normalizeManagedCodexHome(
            paths: paths,
            force: false,
            reason: "startup",
            fileManager: fileManager
        )

        XCTAssertFalse(result.executed)
        XCTAssertEqual(result.reason, "already-normalized")
        XCTAssertNil(result.quarantineURL)
    }

    private func tempDirectory(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
