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
            try ChatArchiveStore.finalizeCheckpoint(
                projectPath: projectPath,
                threadID: threadID,
                turn: summary
            )
        case .failed:
            try ChatArchiveStore.failCheckpoint(
                projectPath: projectPath,
                threadID: threadID,
                turn: summary
            )
        case .pending:
            try ChatArchiveStore.beginCheckpoint(
                projectPath: projectPath,
                threadID: threadID,
                turn: summary
            )
        }
    }
}
