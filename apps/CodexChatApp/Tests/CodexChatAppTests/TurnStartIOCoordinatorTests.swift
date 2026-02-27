import CodexChatCore
@testable import CodexChatShared
import Foundation
import XCTest

final class TurnStartIOCoordinatorTests: XCTestCase {
    func testBeginCheckpointPersistsPendingTurn() async throws {
        let projectRoot = try makeTempDirectory(prefix: "turn-start-io-checkpoint")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let coordinator = TurnStartIOCoordinator()
        let threadID = UUID()
        let turnID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_300_000)

        try await coordinator.beginCheckpoint(
            projectPath: projectRoot.path,
            threadID: threadID,
            turn: ArchivedTurnSummary(
                turnID: turnID,
                timestamp: timestamp,
                status: .pending,
                userText: "Question",
                assistantText: "",
                actions: []
            )
        )

        let turns = try ChatArchiveStore.loadRecentTurns(
            projectPath: projectRoot.path,
            threadID: threadID,
            limit: 10
        )
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.status, .pending)
        XCTAssertEqual(turns.first?.turnID, turnID)
    }

    func testCaptureModSnapshotCopiesGlobalAndProjectMods() async throws {
        let projectRoot = try makeTempDirectory(prefix: "turn-start-io-project")
        let storageRoot = try makeTempDirectory(prefix: "turn-start-io-storage")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: storageRoot)
        }

        let previousRoot = UserDefaults.standard.string(forKey: CodexChatStoragePaths.rootPreferenceKey)
        UserDefaults.standard.set(storageRoot.path, forKey: CodexChatStoragePaths.rootPreferenceKey)
        defer {
            if let previousRoot {
                UserDefaults.standard.set(previousRoot, forKey: CodexChatStoragePaths.rootPreferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CodexChatStoragePaths.rootPreferenceKey)
            }
        }

        let fileManager = FileManager.default
        let globalModsRoot = storageRoot
            .appendingPathComponent("global", isDirectory: true)
            .appendingPathComponent("mods", isDirectory: true)
        try fileManager.createDirectory(at: globalModsRoot, withIntermediateDirectories: true)
        try "global".write(
            to: globalModsRoot.appendingPathComponent("global-mod.txt"),
            atomically: true,
            encoding: .utf8
        )

        let projectModsRoot = projectRoot.appendingPathComponent("mods", isDirectory: true)
        try fileManager.createDirectory(at: projectModsRoot, withIntermediateDirectories: true)
        try "project".write(
            to: projectModsRoot.appendingPathComponent("project-mod.txt"),
            atomically: true,
            encoding: .utf8
        )

        let coordinator = TurnStartIOCoordinator()
        let snapshot = try await coordinator.captureModSnapshot(
            projectPath: projectRoot.path,
            threadID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_300_100)
        )

        XCTAssertTrue(fileManager.fileExists(atPath: snapshot.globalSnapshotURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: snapshot.globalSnapshotURL.appendingPathComponent("global-mod.txt").path))
        XCTAssertTrue(snapshot.projectRootExisted)
        XCTAssertTrue(fileManager.fileExists(atPath: snapshot.projectSnapshotURL?.path ?? ""))
        XCTAssertTrue(fileManager.fileExists(atPath: snapshot.projectSnapshotURL?.appendingPathComponent("project-mod.txt").path ?? ""))
    }

    func testBeginCheckpointRecordsPerformanceSample() async throws {
        await PerformanceTracer.shared.reset()

        let projectRoot = try makeTempDirectory(prefix: "turn-start-io-perf-checkpoint")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let coordinator = TurnStartIOCoordinator()
        try await coordinator.beginCheckpoint(
            projectPath: projectRoot.path,
            threadID: UUID(),
            turn: ArchivedTurnSummary(
                turnID: UUID(),
                timestamp: Date(timeIntervalSince1970: 1_700_400_000),
                status: .pending,
                userText: "Perf checkpoint",
                assistantText: "",
                actions: []
            )
        )

        let snapshot = await PerformanceTracer.shared.snapshot(maxRecent: 40)
        XCTAssertTrue(
            snapshot.operations.contains(where: { $0.name == "runtime.turnStartIO.checkpoint" })
        )
        await PerformanceTracer.shared.reset()
    }

    func testCaptureModSnapshotRecordsPerformanceSample() async throws {
        await PerformanceTracer.shared.reset()

        let projectRoot = try makeTempDirectory(prefix: "turn-start-io-perf-project")
        let storageRoot = try makeTempDirectory(prefix: "turn-start-io-perf-storage")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: storageRoot)
        }

        let previousRoot = UserDefaults.standard.string(forKey: CodexChatStoragePaths.rootPreferenceKey)
        UserDefaults.standard.set(storageRoot.path, forKey: CodexChatStoragePaths.rootPreferenceKey)
        defer {
            if let previousRoot {
                UserDefaults.standard.set(previousRoot, forKey: CodexChatStoragePaths.rootPreferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CodexChatStoragePaths.rootPreferenceKey)
            }
        }

        let fileManager = FileManager.default
        let globalModsRoot = storageRoot
            .appendingPathComponent("global", isDirectory: true)
            .appendingPathComponent("mods", isDirectory: true)
        try fileManager.createDirectory(at: globalModsRoot, withIntermediateDirectories: true)
        try "global".write(
            to: globalModsRoot.appendingPathComponent("global-mod.txt"),
            atomically: true,
            encoding: .utf8
        )

        let projectModsRoot = projectRoot.appendingPathComponent("mods", isDirectory: true)
        try fileManager.createDirectory(at: projectModsRoot, withIntermediateDirectories: true)
        try "project".write(
            to: projectModsRoot.appendingPathComponent("project-mod.txt"),
            atomically: true,
            encoding: .utf8
        )

        let coordinator = TurnStartIOCoordinator()
        _ = try await coordinator.captureModSnapshot(
            projectPath: projectRoot.path,
            threadID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_400_100)
        )

        let snapshot = await PerformanceTracer.shared.snapshot(maxRecent: 40)
        XCTAssertTrue(
            snapshot.operations.contains(where: { $0.name == "runtime.turnStartIO.snapshot" })
        )
        await PerformanceTracer.shared.reset()
    }

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
