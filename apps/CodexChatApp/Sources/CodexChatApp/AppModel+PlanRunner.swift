import CodexChatCore
import Foundation

extension AppModel {
    enum PlanRunnerExecutionError: LocalizedError {
        case missingSelection
        case emptyPlan
        case timeoutWaitingForTurn
        case completionMarkersMissing

        var errorDescription: String? {
            switch self {
            case .missingSelection:
                "Select a project and thread before running a plan."
            case .emptyPlan:
                "Provide a plan file or plan text before running."
            case .timeoutWaitingForTurn:
                "Timed out waiting for the runtime turn to complete."
            case .completionMarkersMissing:
                "No completion markers were found. Ask the runtime to emit TASK_COMPLETE / TASK_FAILED markers."
            }
        }
    }

    func openPlanRunnerSheet(pathHint: String? = nil) {
        if let pathHint {
            planRunnerSourcePath = pathHint
        }
        isPlanRunnerSheetVisible = true
        planRunnerStatusMessage = nil

        Task {
            await hydratePlanRunnerDraftFromPathIfNeeded()
            await loadLatestPlanRunForSelectedThread()
        }
    }

    func closePlanRunnerSheet() {
        isPlanRunnerSheetVisible = false
    }

    func hydratePlanRunnerDraftFromPathIfNeeded() async {
        let sourcePath = planRunnerSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourcePath.isEmpty else {
            return
        }

        do {
            let expanded = (sourcePath as NSString).expandingTildeInPath
            let resolvedURL = URL(fileURLWithPath: expanded)
            guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
                planRunnerStatusMessage = "Plan file not found at \(resolvedURL.path)."
                return
            }
            planRunnerDraftText = try String(contentsOf: resolvedURL)
            planRunnerSourcePath = resolvedURL.path
        } catch {
            planRunnerStatusMessage = "Failed to read plan file: \(error.localizedDescription)"
        }
    }

    func loadLatestPlanRunForSelectedThread() async {
        guard let selectedThreadID,
              let planRunRepository
        else {
            activePlanRun = nil
            planRunnerTaskStates = []
            return
        }

        do {
            let runs = try await planRunRepository.list(threadID: selectedThreadID)
            guard let latest = runs.first else {
                activePlanRun = nil
                planRunnerTaskStates = []
                return
            }

            activePlanRun = latest
            if let planRunTaskRepository {
                planRunnerTaskStates = try await planRunTaskRepository.list(planRunID: latest.id)
                    .sorted(by: { $0.taskID.localizedStandardCompare($1.taskID) == .orderedAscending })
            } else {
                planRunnerTaskStates = []
            }
        } catch {
            planRunnerStatusMessage = "Failed loading latest plan run: \(error.localizedDescription)"
        }
    }

    func startPlanRunnerExecution() {
        guard !isPlanRunnerExecuting else {
            return
        }

        guard let selectedThreadID,
              let selectedProjectID,
              let selectedProject = projects.first(where: { $0.id == selectedProjectID })
        else {
            planRunnerStatusMessage = PlanRunnerExecutionError.missingSelection.localizedDescription
            return
        }

        planRunnerTask?.cancel()

        planRunnerTask = Task {
            await runPlanExecutionLoop(
                threadID: selectedThreadID,
                projectID: selectedProjectID,
                projectPath: selectedProject.path
            )
        }
    }

    func cancelPlanRunnerExecution() {
        planRunnerTask?.cancel()
        planRunnerTask = nil
        isPlanRunnerExecuting = false
        planRunnerStatusMessage = "Cancelled plan runner execution."

        Task {
            await updateActivePlanRunStatus(status: .cancelled, lastError: "Cancelled by user")
        }
    }

    private func runPlanExecutionLoop(
        threadID: UUID,
        projectID: UUID,
        projectPath: String
    ) async {
        isPlanRunnerExecuting = true
        defer {
            isPlanRunnerExecuting = false
            planRunnerTask = nil
        }

        do {
            let planText = try await resolvedPlanText()
            let document = try PlanParser.parse(planText)
            let scheduler = try PlanScheduler(document: document)

            let planRun = try await initializePlanRun(
                document: document,
                threadID: threadID,
                projectID: projectID
            )
            activePlanRun = planRun

            var taskStates = planRunnerTaskStates
            planRunnerStatusMessage = "Running plan with \(taskStates.count) task(s)."

            while !Task.isCancelled {
                let executionState = planExecutionState(from: taskStates)
                if scheduler.isComplete(state: executionState) {
                    planRunnerTaskStates = taskStates
                    await updateActivePlanRunStatus(status: .completed, lastError: nil)
                    planRunnerStatusMessage = "Plan run completed successfully."
                    appendEntry(
                        .actionCard(
                            ActionCard(
                                threadID: threadID,
                                method: "plan/run/completed",
                                title: "Plan run completed",
                                detail: "Completed \(taskStates.count) task(s)."
                            )
                        ),
                        to: threadID
                    )
                    return
                }

                let batch = scheduler.nextUnblockedBatch(
                    state: executionState,
                    preferredBatchSize: planRunnerPreferredBatchSize,
                    multiAgentEnabled: isMultiAgentEnabledForPlanRunner
                )

                guard !batch.isEmpty else {
                    let unresolved = taskStates.filter { $0.status == .pending || $0.status == .running }
                    let reason = unresolved.isEmpty
                        ? "No runnable tasks remained."
                        : "No unblocked tasks remained. Verify dependency graph and task markers."
                    await updateActivePlanRunStatus(status: .failed, lastError: reason)
                    planRunnerStatusMessage = reason
                    appendEntry(
                        .actionCard(
                            ActionCard(
                                threadID: threadID,
                                method: "plan/run/failed",
                                title: "Plan run blocked",
                                detail: reason
                            )
                        ),
                        to: threadID
                    )
                    return
                }

                taskStates = markTasks(batch.map(\.id), status: .running, in: taskStates)
                planRunnerTaskStates = taskStates
                try await persistPlanTasks(taskStates)

                let batchDescription = batch.map { "\($0.id): \($0.title)" }.joined(separator: "\n")
                appendEntry(
                    .actionCard(
                        ActionCard(
                            threadID: threadID,
                            method: "plan/run/batch",
                            title: "Plan batch started",
                            detail: batchDescription
                        )
                    ),
                    to: threadID
                )

                let baseline = Date()
                let prompt = orchestrationPrompt(for: batch, in: document)
                try await dispatchNow(
                    text: prompt,
                    threadID: threadID,
                    projectID: projectID,
                    projectPath: projectPath,
                    sourceQueueItemID: nil
                )

                try await waitForPlanRunnerTurnCompletion(timeoutSeconds: 900)
                let assistantResponse = assistantResponseSince(
                    threadID: threadID,
                    baseline: baseline
                )
                let markers = parseCompletionMarkers(from: assistantResponse)

                if markers.completed.isEmpty, markers.failed.isEmpty {
                    if batch.count == 1 {
                        taskStates = markTasks([batch[0].id], status: .completed, in: taskStates)
                        planRunnerStatusMessage = "No explicit markers returned; advanced single task \(batch[0].id) as completed."
                    } else {
                        throw PlanRunnerExecutionError.completionMarkersMissing
                    }
                } else {
                    if !markers.completed.isEmpty {
                        taskStates = markTasks(markers.completed, status: .completed, in: taskStates)
                    }
                    if !markers.failed.isEmpty {
                        taskStates = markTasks(Array(markers.failed.keys), status: .failed, in: taskStates)
                    }
                }

                planRunnerTaskStates = taskStates
                try await persistPlanTasks(taskStates)
                await refreshActivePlanRunProgress(from: taskStates)
            }

            await updateActivePlanRunStatus(status: .cancelled, lastError: "Cancelled")
        } catch {
            let message = error.localizedDescription
            planRunnerStatusMessage = "Plan run failed: \(message)"
            appendLog(.error, "Plan runner failed: \(message)")
            await updateActivePlanRunStatus(status: .failed, lastError: message)
        }
    }

    private func resolvedPlanText() async throws -> String {
        let trimmedPath = planRunnerSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPath.isEmpty {
            let expanded = (trimmedPath as NSString).expandingTildeInPath
            let path = URL(fileURLWithPath: expanded).path
            let text = try String(contentsOfFile: path)
            planRunnerSourcePath = path
            planRunnerDraftText = text
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PlanRunnerExecutionError.emptyPlan
            }
            return text
        }

        let text = planRunnerDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw PlanRunnerExecutionError.emptyPlan
        }
        return text
    }

    private func initializePlanRun(
        document: PlanDocument,
        threadID: UUID,
        projectID: UUID
    ) async throws -> PlanRunRecord {
        var planRun = PlanRunRecord(
            threadID: threadID,
            projectID: projectID,
            title: planRunTitle,
            sourcePath: normalizedPlanSourcePath,
            status: .running,
            totalTasks: document.tasks.count,
            completedTasks: 0,
            lastError: nil
        )

        if let planRunRepository {
            planRun = try await planRunRepository.upsert(planRun)
        }

        let initialTasks = document.tasks.map { task in
            PlanRunTaskRecord(
                planRunID: planRun.id,
                taskID: task.id,
                title: task.title,
                dependencyIDs: task.dependencies,
                status: .pending
            )
        }

        planRunnerTaskStates = initialTasks
        if let planRunTaskRepository {
            try await planRunTaskRepository.replace(planRunID: planRun.id, tasks: initialTasks)
        }

        return planRun
    }

    private func persistPlanTasks(_ tasks: [PlanRunTaskRecord]) async throws {
        guard let activePlanRun,
              let planRunTaskRepository
        else {
            return
        }

        try await planRunTaskRepository.replace(planRunID: activePlanRun.id, tasks: tasks)
    }

    private func refreshActivePlanRunProgress(from tasks: [PlanRunTaskRecord]) async {
        let completedCount = tasks.count(where: { $0.status == .completed })
        if var run = activePlanRun {
            run.completedTasks = completedCount
            run.totalTasks = max(run.totalTasks, tasks.count)
            run.updatedAt = Date()
            if let planRunRepository,
               let persisted = try? await planRunRepository.upsert(run)
            {
                activePlanRun = persisted
            } else {
                activePlanRun = run
            }
        }
    }

    private func updateActivePlanRunStatus(status: PlanRunStatus, lastError: String?) async {
        guard var run = activePlanRun else {
            return
        }

        run.status = status
        run.lastError = lastError
        run.completedTasks = planRunnerTaskStates.count(where: { $0.status == .completed })
        run.totalTasks = max(run.totalTasks, planRunnerTaskStates.count)
        run.updatedAt = Date()

        if let planRunRepository,
           let persisted = try? await planRunRepository.upsert(run)
        {
            activePlanRun = persisted
        } else {
            activePlanRun = run
        }
    }

    private func planExecutionState(from tasks: [PlanRunTaskRecord]) -> PlanExecutionState {
        PlanExecutionState(
            completedTaskIDs: Set(tasks.filter { $0.status == .completed }.map(\.taskID)),
            inFlightTaskIDs: Set(tasks.filter { $0.status == .running }.map(\.taskID)),
            failedTaskIDs: Set(tasks.filter { $0.status == .failed }.map(\.taskID))
        )
    }

    private func markTasks(
        _ taskIDs: [String],
        status: PlanTaskRunStatus,
        in tasks: [PlanRunTaskRecord]
    ) -> [PlanRunTaskRecord] {
        let taskIDSet = Set(taskIDs)
        return tasks.map { task in
            guard taskIDSet.contains(task.taskID) else {
                return task
            }
            var updated = task
            updated.status = status
            updated.updatedAt = Date()
            return updated
        }
    }

    private func orchestrationPrompt(for batch: [PlanTask], in document: PlanDocument) -> String {
        let dependencySummary = batch.map { task in
            let dependencies = task.dependencies.isEmpty ? "none" : task.dependencies.joined(separator: ", ")
            return "- \(task.id): \(task.title) (depends on: \(dependencies))"
        }.joined(separator: "\n")

        let multiAgentGuidance = isMultiAgentEnabledForPlanRunner
            ? "Multi-agent execution is enabled. You may parallelize independent tasks in this batch."
            : "Multi-agent execution is disabled. Execute tasks sequentially in this batch."

        return """
        You are executing a dependency-aware plan batch.

        Total plan tasks: \(document.tasks.count)
        Current batch:
        \(dependencySummary)

        \(multiAgentGuidance)

        Requirements:
        1. Execute only the listed batch tasks.
        2. Return explicit completion markers:
           TASK_COMPLETE: <task-id>
           TASK_FAILED: <task-id> :: <reason>
        3. Include one marker per task in this batch.
        4. Keep output concise and decision-ready.
        """
    }

    private func waitForPlanRunnerTurnCompletion(timeoutSeconds: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if activeTurnThreadIDs.isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        throw PlanRunnerExecutionError.timeoutWaitingForTurn
    }

    private func assistantResponseSince(threadID: UUID, baseline: Date) -> String {
        guard let entries = transcriptStore[threadID] else {
            return ""
        }

        let messages = entries.compactMap { entry -> ChatMessage? in
            guard case let .message(message) = entry,
                  message.role == .assistant,
                  message.createdAt >= baseline
            else {
                return nil
            }
            return message
        }

        return messages
            .map(\.text)
            .joined(separator: "\n\n")
    }

    private func parseCompletionMarkers(from text: String) -> (completed: [String], failed: [String: String]) {
        let lines = text.components(separatedBy: .newlines)
        var completed: [String] = []
        var failed: [String: String] = [:]

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }

            if line.uppercased().hasPrefix("TASK_COMPLETE:") {
                let payload = line.dropFirst("TASK_COMPLETE:".count)
                let ids = parseTaskIDTokens(from: String(payload))
                completed.append(contentsOf: ids)
                continue
            }

            if line.uppercased().hasPrefix("TASK_FAILED:") {
                let payload = String(line.dropFirst("TASK_FAILED:".count))
                let components = payload.components(separatedBy: "::")
                let ids = parseTaskIDTokens(from: components.first ?? "")
                let reason = components.count > 1
                    ? components.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)
                    : "Failed"

                for id in ids {
                    failed[id] = reason
                }
            }
        }

        return (Array(Set(completed)), failed)
    }

    private func parseTaskIDTokens(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*"#) else {
            return []
        }

        let fullRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        var ids: [String] = []
        var seen = Set<String>()

        for match in matches {
            guard let tokenRange = Range(match.range, in: text) else {
                continue
            }
            let token = String(text[tokenRange])
            guard token.rangeOfCharacter(from: .decimalDigits) != nil else {
                continue
            }
            if seen.insert(token).inserted {
                ids.append(token)
            }
        }

        return ids
    }

    private var planRunTitle: String {
        let trimmedPath = planRunnerSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPath.isEmpty {
            return URL(fileURLWithPath: trimmedPath).lastPathComponent
        }
        return "Plan run"
    }

    private var normalizedPlanSourcePath: String? {
        let trimmed = planRunnerSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return (trimmed as NSString).expandingTildeInPath
    }

    var isMultiAgentEnabledForPlanRunner: Bool {
        codexConfigDocument
            .value(at: [.key("features"), .key("multi_agent")])?
            .booleanValue ?? true
    }
}
