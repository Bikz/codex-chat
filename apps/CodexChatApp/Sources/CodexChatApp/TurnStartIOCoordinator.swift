import CodexChatCore
import Foundation

actor TurnStartIOCoordinator {
    func beginCheckpoint(
        projectPath: String,
        threadID: UUID,
        turn: ArchivedTurnSummary
    ) throws {
        _ = try ChatArchiveStore.beginCheckpoint(
            projectPath: projectPath,
            threadID: threadID,
            turn: turn
        )
    }

    func captureModSnapshot(
        projectPath: String,
        threadID: UUID,
        startedAt: Date,
        fileManager: FileManager = .default
    ) throws -> ModEditSafety.Snapshot {
        let snapshotsRootURL = try Self.modSnapshotsRootURL(fileManager: fileManager)
        let globalRootPath = try AppModel.globalModsRootPath(fileManager: fileManager)
        let projectRootPath = AppModel.projectModsRootPath(projectPath: projectPath)

        return try ModEditSafety.captureSnapshot(
            snapshotsRootURL: snapshotsRootURL,
            globalRootPath: globalRootPath,
            projectRootPath: projectRootPath,
            threadID: threadID,
            startedAt: startedAt,
            fileManager: fileManager
        )
    }

    private static func modSnapshotsRootURL(fileManager: FileManager = .default) throws -> URL {
        let storagePaths = CodexChatStoragePaths.current(fileManager: fileManager)
        let root = storagePaths.modSnapshotsURL
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
