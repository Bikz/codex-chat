import CodexChatCore
import Foundation

actor TurnStartIOCoordinator {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let maxConcurrentJobs: Int
    private var activeJobCount: Int = 0
    private var waiters: [Waiter] = []

    init(maxConcurrentJobs: Int = TurnStartIOCoordinator.defaultMaxConcurrentJobs) {
        self.maxConcurrentJobs = max(1, maxConcurrentJobs)
    }

    static var defaultMaxConcurrentJobs: Int {
        let key = "CODEXCHAT_TURN_START_IO_MAX_CONCURRENCY"
        if let configured = ProcessInfo.processInfo.environment[key],
           let parsed = Int(configured),
           parsed > 0
        {
            return min(parsed, 16)
        }

        return 4
    }

    func beginCheckpoint(
        projectPath: String,
        threadID: UUID,
        turn: ArchivedTurnSummary
    ) async throws {
        try await reserveJobSlot()
        defer { releaseJobSlot() }
        let startedAt = Date()

        try await runBlockingIO {
            _ = try ChatArchiveStore.beginCheckpoint(
                projectPath: projectPath,
                threadID: threadID,
                turn: turn
            )
        }

        let durationMS = max(0, Date().timeIntervalSince(startedAt) * 1000)
        await PerformanceTracer.shared.record(
            name: "runtime.turnStartIO.checkpoint",
            durationMS: durationMS
        )
    }

    func captureModSnapshot(
        projectPath: String,
        threadID: UUID,
        startedAt: Date
    ) async throws -> ModEditSafety.Snapshot {
        try await reserveJobSlot()
        defer { releaseJobSlot() }
        let operationStartedAt = Date()

        let snapshot = try await runBlockingIO {
            let fileManager = FileManager.default
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

        let durationMS = max(0, Date().timeIntervalSince(operationStartedAt) * 1000)
        await PerformanceTracer.shared.record(
            name: "runtime.turnStartIO.snapshot",
            durationMS: durationMS
        )
        return snapshot
    }

    private static func modSnapshotsRootURL(fileManager: FileManager = .default) throws -> URL {
        let storagePaths = CodexChatStoragePaths.current(fileManager: fileManager)
        let root = storagePaths.modSnapshotsURL
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func reserveJobSlot() async throws {
        try Task.checkCancellation()

        if activeJobCount < maxConcurrentJobs {
            activeJobCount += 1
            return
        }

        let waiterID = UUID()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append(Waiter(id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task {
                await self.cancel(waiterID: waiterID)
            }
        }

        guard acquired else {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    private func releaseJobSlot() {
        activeJobCount = max(0, activeJobCount - 1)
        promoteWaitersIfPossible()
    }

    private func promoteWaitersIfPossible() {
        while activeJobCount < maxConcurrentJobs, !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            activeJobCount += 1
            waiter.continuation.resume(returning: true)
        }
    }

    private func cancel(waiterID: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else {
            return
        }

        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    private func runBlockingIO<T: Sendable>(
        operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let value = try operation()
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
