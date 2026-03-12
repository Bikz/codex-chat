@testable import CodexChatShared
import Foundation
import XCTest

final class CodexStorageMigrationCoordinatorTests: XCTestCase {
    func testSharedHomeHandoffCopiesMissingArtifactsAndDoesNotOverwrite() throws {
        let fileManager = FileManager.default
        let root = tempDirectory(prefix: "codexchat-storage-handoff")
        defer { try? fileManager.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        let homes = makeTestResolvedCodexHomes(root: root, storagePaths: paths)
        try paths.ensureRootStructure(fileManager: fileManager)

        try fileManager.createDirectory(at: paths.legacyManagedCodexHomeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.legacyManagedAgentsHomeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homes.activeCodexHomeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homes.activeAgentsHomeURL, withIntermediateDirectories: true)

        try write("existing-config", to: homes.activeCodexConfigURL)
        try write("legacy-config", to: paths.legacyManagedCodexConfigURL)
        try write("auth", to: paths.legacyManagedCodexHomeURL.appendingPathComponent("auth.json"))
        try write("history", to: paths.legacyManagedCodexHomeURL.appendingPathComponent("history.jsonl"))
        try write("credentials", to: paths.legacyManagedCodexHomeURL.appendingPathComponent(".credentials.json"))
        try write("agents", to: paths.legacyManagedCodexHomeURL.appendingPathComponent("AGENTS.md"))
        try write("agents-override", to: paths.legacyManagedCodexHomeURL.appendingPathComponent("AGENTS.override.md"))
        try write("memory", to: paths.legacyManagedCodexHomeURL.appendingPathComponent("memory.md"))
        try write(
            "legacy codex skill",
            to: paths.legacyManagedCodexHomeURL
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent("codex-skill", isDirectory: true)
                .appendingPathComponent("SKILL.md", isDirectory: false)
        )
        try write(
            "legacy agent skill",
            to: paths.legacyManagedAgentsHomeURL
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent("agent-skill", isDirectory: true)
                .appendingPathComponent("SKILL.md", isDirectory: false)
        )

        let result = try CodexChatStorageMigrationCoordinator.performSharedHomeHandoffIfNeeded(
            paths: paths,
            homes: homes,
            fileManager: fileManager
        )

        XCTAssertTrue(result.executed)
        XCTAssertEqual(try String(contentsOf: homes.activeCodexConfigURL, encoding: .utf8), "existing-config")
        XCTAssertTrue(fileManager.fileExists(atPath: homes.activeCodexHomeURL.appendingPathComponent("auth.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: homes.activeCodexHomeURL.appendingPathComponent("history.jsonl").path))
        XCTAssertTrue(fileManager.fileExists(atPath: homes.activeCodexHomeURL.appendingPathComponent(".credentials.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: homes.activeCodexHomeURL.appendingPathComponent("AGENTS.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: homes.activeCodexHomeURL.appendingPathComponent("AGENTS.override.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: homes.activeCodexHomeURL.appendingPathComponent("memory.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: homes.activeCodexHomeURL.appendingPathComponent("skills/codex-skill/SKILL.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: homes.activeAgentsHomeURL.appendingPathComponent("skills/agent-skill/SKILL.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.sharedCodexHomeHandoffReportURL.path))

        let report = try XCTUnwrap(
            CodexChatStorageMigrationCoordinator.readLastSharedCodexHomeHandoffReport(
                paths: paths,
                fileManager: fileManager
            )
        )
        XCTAssertEqual(report.activeCodexHomePath, homes.activeCodexHomeURL.path)
        XCTAssertEqual(report.activeAgentsHomePath, homes.activeAgentsHomeURL.path)
        XCTAssertEqual(report.source, homes.source.rawValue)
        XCTAssertTrue(report.skippedEntries.contains("config.toml:exists"))
    }

    func testSharedHomeHandoffSkipsRepeatedMatchingDestination() throws {
        let fileManager = FileManager.default
        let root = tempDirectory(prefix: "codexchat-storage-handoff-repeat")
        defer { try? fileManager.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        let homes = makeTestResolvedCodexHomes(root: root, storagePaths: paths)
        try paths.ensureRootStructure(fileManager: fileManager)
        try fileManager.createDirectory(at: paths.legacyManagedCodexHomeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homes.activeCodexHomeURL, withIntermediateDirectories: true)
        try write("auth", to: paths.legacyManagedCodexHomeURL.appendingPathComponent("auth.json"))

        _ = try CodexChatStorageMigrationCoordinator.performSharedHomeHandoffIfNeeded(
            paths: paths,
            homes: homes,
            fileManager: fileManager
        )
        let second = try CodexChatStorageMigrationCoordinator.performSharedHomeHandoffIfNeeded(
            paths: paths,
            homes: homes,
            fileManager: fileManager
        )

        XCTAssertFalse(second.executed)
    }

    func testArchiveLegacyManagedHomesMovesLegacyManagedCopies() throws {
        let fileManager = FileManager.default
        let root = tempDirectory(prefix: "codexchat-storage-archive")
        defer { try? fileManager.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure(fileManager: fileManager)

        try write("legacy config", to: paths.legacyManagedCodexConfigURL)
        try write(
            "legacy agent skill",
            to: paths.legacyManagedAgentsHomeURL
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent("agent-skill", isDirectory: true)
                .appendingPathComponent("SKILL.md", isDirectory: false)
        )

        let result = try CodexChatStorageMigrationCoordinator.archiveLegacyManagedHomes(
            paths: paths,
            fileManager: fileManager
        )

        XCTAssertTrue(result.executed)
        let archiveRootURL = try XCTUnwrap(result.archiveRootURL)
        XCTAssertTrue(fileManager.fileExists(atPath: archiveRootURL.appendingPathComponent("codex-home").path))
        XCTAssertTrue(fileManager.fileExists(atPath: archiveRootURL.appendingPathComponent("agents-home").path))
        XCTAssertFalse(fileManager.fileExists(atPath: paths.legacyManagedCodexHomeURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: paths.legacyManagedAgentsHomeURL.path))

        let report = try XCTUnwrap(
            CodexChatStorageMigrationCoordinator.readLastLegacyManagedHomesArchiveReport(
                paths: paths,
                fileManager: fileManager
            )
        )
        XCTAssertEqual(report.archiveRootPath, archiveRootURL.path)
        XCTAssertEqual(report.archivedEntries, ["agents-home", "codex-home"])
    }

    func testRepairManagedCodexHomeSkillSymlinksRelinksBrokenEntriesToLegacyManagedAgentsHome() throws {
        let fileManager = FileManager.default
        let root = tempDirectory(prefix: "codexchat-storage-repair-symlink")
        defer { try? fileManager.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure(fileManager: fileManager)

        let managedSkillURL = paths.legacyManagedAgentsHomeURL
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("agent-browser", isDirectory: true)
            .appendingPathComponent("SKILL.md", isDirectory: false)
        try write("managed skill", to: managedSkillURL)

        let staleLink = paths.legacyManagedCodexHomeURL
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("agent-browser", isDirectory: true)
        try fileManager.createDirectory(at: staleLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            atPath: staleLink.path,
            withDestinationPath: "../../missing-home/skills/agent-browser"
        )

        XCTAssertFalse(fileManager.fileExists(atPath: staleLink.path))

        let result = try CodexChatStorageMigrationCoordinator.repairManagedCodexHomeSkillSymlinksIfNeeded(
            paths: paths,
            fileManager: fileManager
        )

        XCTAssertEqual(result.relinkedEntries, ["agent-browser"])
        XCTAssertTrue(result.removedEntries.isEmpty)
        XCTAssertTrue(fileManager.fileExists(atPath: staleLink.path))
        XCTAssertTrue(fileManager.fileExists(atPath: staleLink.appendingPathComponent("SKILL.md").path))
    }

    func testRepairManagedCodexHomeSkillSymlinksRemovesBrokenEntriesWithoutReplacement() throws {
        let fileManager = FileManager.default
        let root = tempDirectory(prefix: "codexchat-storage-remove-broken-symlink")
        defer { try? fileManager.removeItem(at: root) }

        let paths = CodexChatStoragePaths(rootURL: root)
        try paths.ensureRootStructure(fileManager: fileManager)

        let staleLink = paths.legacyManagedCodexHomeURL
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("missing-skill", isDirectory: true)
        try fileManager.createDirectory(at: staleLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            atPath: staleLink.path,
            withDestinationPath: "../../agents-home/skills/missing-skill"
        )

        XCTAssertFalse(fileManager.fileExists(atPath: staleLink.path))

        let result = try CodexChatStorageMigrationCoordinator.repairManagedCodexHomeSkillSymlinksIfNeeded(
            paths: paths,
            fileManager: fileManager
        )

        XCTAssertTrue(result.relinkedEntries.isEmpty)
        XCTAssertEqual(result.removedEntries, ["missing-skill"])
        XCTAssertFalse(fileManager.fileExists(atPath: staleLink.path))
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
