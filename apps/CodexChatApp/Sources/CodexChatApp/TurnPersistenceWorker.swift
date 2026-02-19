import Foundation

actor TurnPersistenceWorker {
    static let shared = TurnPersistenceWorker()

    func persistArchive(
        projectPath: String,
        threadID: UUID,
        summary: ArchivedTurnSummary,
        turnStatus: ChatArchiveTurnStatus
    ) throws -> URL {
        switch turnStatus {
        case .completed:
            return try ChatArchiveStore.finalizeCheckpoint(
                projectPath: projectPath,
                threadID: threadID,
                turn: summary
            )
        case .failed:
            return try ChatArchiveStore.failCheckpoint(
                projectPath: projectPath,
                threadID: threadID,
                turn: summary
            )
        case .pending:
            return try ChatArchiveStore.beginCheckpoint(
                projectPath: projectPath,
                threadID: threadID,
                turn: summary
            )
        }
    }
}
