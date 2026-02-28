import CodexChatCore
import CodexKit
import Foundation

extension AppModel {
    private struct RuntimeThreadPrewarmTarget: Sendable {
        let threadID: UUID
        let projectPath: String
        let safetyConfiguration: RuntimeSafetyConfiguration
    }

    private struct RuntimeThreadPrewarmOutcome: Sendable {
        let threadID: UUID
        let status: String
    }

    private var canRunRuntimeThreadPrewarm: Bool {
        runtimePool != nil
            && runtimeStatus == .connected
            && runtimeIssue == nil
            && isSignedInForRuntime
    }

    func cancelRuntimeThreadPrewarm() {
        runtimeThreadPrewarmGeneration = runtimeThreadPrewarmGeneration &+ 1
        runtimeThreadPrewarmTask?.cancel()
        runtimeThreadPrewarmTask = nil
    }

    func scheduleRuntimeThreadPrewarm(primaryThreadID: UUID?, reason: String) {
        runtimeThreadPrewarmGeneration = runtimeThreadPrewarmGeneration &+ 1
        let generation = runtimeThreadPrewarmGeneration
        runtimeThreadPrewarmTask?.cancel()
        runtimeThreadPrewarmTask = nil

        guard canRunRuntimeThreadPrewarm else {
            return
        }

        let targetThreadIDs = runtimeThreadPrewarmTargetThreadIDs(primaryThreadID: primaryThreadID)
        guard !targetThreadIDs.isEmpty else {
            return
        }

        runtimeThreadPrewarmTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await executeRuntimeThreadPrewarm(
                generation: generation,
                reason: reason,
                targetThreadIDs: targetThreadIDs
            )
        }
    }

    func runtimeThreadPrewarmTargetThreadIDs(primaryThreadID: UUID?) -> [UUID] {
        let resolvedPrimaryThreadID = primaryThreadID ?? selectedThreadID
        guard let resolvedPrimaryThreadID else {
            return []
        }

        var targetThreadIDs: [UUID] = []
        targetThreadIDs.reserveCapacity(4)

        func appendThreadID(_ threadID: UUID) {
            guard targetThreadIDs.count < 4 else { return }
            guard !targetThreadIDs.contains(threadID) else { return }
            targetThreadIDs.append(threadID)
        }

        appendThreadID(resolvedPrimaryThreadID)
        let siblingSource = selectedProjectID == generalProject?.id ? generalThreads : threads
        for thread in siblingSource where thread.archivedAt == nil {
            appendThreadID(thread.id)
            if targetThreadIDs.count == 4 {
                break
            }
        }

        return targetThreadIDs
    }

    private func executeRuntimeThreadPrewarm(
        generation: UInt64,
        reason: String,
        targetThreadIDs: [UUID]
    ) async {
        guard runtimeThreadPrewarmGeneration == generation else {
            return
        }

        let batchSpan = await PerformanceTracer.shared.begin(
            name: "runtime.prewarm.batch",
            metadata: [
                "reason": reason,
                "targetCount": "\(targetThreadIDs.count)",
                "selectedThreadID": selectedThreadID?.uuidString ?? "nil",
            ]
        )

        var batchStatus = "ok"
        var outcomes: [RuntimeThreadPrewarmOutcome] = []
        defer {
            let resolvedCount = outcomes.count(where: { $0.status == "resolved" })
            let failedCount = outcomes.count(where: { $0.status == "error" })
            let canceledCount = outcomes.count(where: { $0.status == "cancelled" })
            Task {
                await PerformanceTracer.shared.end(
                    batchSpan,
                    status: batchStatus,
                    extraMetadata: [
                        "resolvedCount": "\(resolvedCount)",
                        "failedCount": "\(failedCount)",
                        "cancelledCount": "\(canceledCount)",
                    ]
                )
            }
            if runtimeThreadPrewarmGeneration == generation {
                runtimeThreadPrewarmTask = nil
            }
        }

        do {
            let targets = try await resolveRuntimeThreadPrewarmTargets(threadIDs: targetThreadIDs)
            guard !targets.isEmpty else {
                batchStatus = "skipped"
                return
            }

            let tasks = targets.map { target in
                Task(priority: .utility) { [weak self] in
                    guard let self else {
                        return RuntimeThreadPrewarmOutcome(threadID: target.threadID, status: "cancelled")
                    }
                    return await runRuntimeThreadPrewarm(target: target, generation: generation)
                }
            }

            for task in tasks {
                let outcome = await task.value
                outcomes.append(outcome)
            }

            if outcomes.contains(where: { $0.status == "error" }) {
                batchStatus = "partial_error"
            } else if outcomes.allSatisfy({ $0.status == "cancelled" }) {
                batchStatus = "cancelled"
            }
        } catch is CancellationError {
            batchStatus = "cancelled"
        } catch {
            batchStatus = "error"
            appendLog(.warning, "Runtime thread prewarm batch failed: \(error.localizedDescription)")
        }
    }

    private func runRuntimeThreadPrewarm(
        target: RuntimeThreadPrewarmTarget,
        generation: UInt64
    ) async -> RuntimeThreadPrewarmOutcome {
        let threadSpan = await PerformanceTracer.shared.begin(
            name: "runtime.prewarm.thread",
            metadata: ["threadID": target.threadID.uuidString]
        )

        var status = "resolved"
        defer {
            Task {
                await PerformanceTracer.shared.end(
                    threadSpan,
                    status: status,
                    extraMetadata: ["status": status]
                )
            }
        }

        guard runtimeThreadPrewarmGeneration == generation else {
            status = "cancelled"
            return RuntimeThreadPrewarmOutcome(threadID: target.threadID, status: status)
        }

        do {
            _ = try await ensureRuntimeThreadIDForPrewarm(
                for: target.threadID,
                projectPath: target.projectPath,
                safetyConfiguration: target.safetyConfiguration
            )
            return RuntimeThreadPrewarmOutcome(threadID: target.threadID, status: status)
        } catch is CancellationError {
            status = "cancelled"
            return RuntimeThreadPrewarmOutcome(threadID: target.threadID, status: status)
        } catch {
            status = "error"
            appendLog(
                .warning,
                "Runtime thread prewarm failed for local thread \(target.threadID.uuidString): \(error.localizedDescription)"
            )
            return RuntimeThreadPrewarmOutcome(threadID: target.threadID, status: status)
        }
    }

    private func resolveRuntimeThreadPrewarmTargets(threadIDs: [UUID]) async throws -> [RuntimeThreadPrewarmTarget] {
        var targets: [RuntimeThreadPrewarmTarget] = []
        targets.reserveCapacity(threadIDs.count)

        for threadID in threadIDs {
            guard let (thread, project) = try await resolveThreadAndProjectForPrewarm(threadID: threadID) else {
                appendLog(.debug, "Skipping runtime prewarm for unresolved thread \(threadID.uuidString)")
                continue
            }

            let preferredWebSearch = effectiveWebSearchMode(for: thread.id, project: project)
            let safetySettingsOverride = threadComposerOverridesByThreadID[thread.id]?.safetyOverride
            let safetyConfiguration = runtimeSafetyConfiguration(
                for: project,
                preferredWebSearch: preferredWebSearch,
                threadSafetyOverride: safetySettingsOverride
            )
            targets.append(
                RuntimeThreadPrewarmTarget(
                    threadID: thread.id,
                    projectPath: project.path,
                    safetyConfiguration: safetyConfiguration
                )
            )
        }

        return targets
    }

    private func resolveThreadAndProjectForPrewarm(
        threadID: UUID
    ) async throws -> (ThreadRecord, ProjectRecord)? {
        let inMemoryThread = (threads + generalThreads + archivedThreads).first(where: { $0.id == threadID })
        let thread: ThreadRecord? = if let inMemoryThread {
            inMemoryThread
        } else {
            try await threadRepository?.getThread(id: threadID)
        }

        guard let thread else {
            return nil
        }

        if let cachedProject = projects.first(where: { $0.id == thread.projectId }) {
            return (thread, cachedProject)
        }

        guard let project = try await projectRepository?.getProject(id: thread.projectId) else {
            return nil
        }

        return (thread, project)
    }
}
