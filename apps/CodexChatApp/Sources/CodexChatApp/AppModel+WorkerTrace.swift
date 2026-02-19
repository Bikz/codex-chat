import CodexChatCore
import CodexKit
import Foundation

extension AppModel {
    func captureWorkerTraceIfPresent(
        runtimeAction: RuntimeAction,
        threadID: UUID,
        transcriptDetail: String
    ) {
        guard let trace = runtimeAction.workerTrace else {
            return
        }

        let sanitizedTrace = sanitizeWorkerTrace(trace)
        let entry = WorkerTraceEntry(
            threadID: threadID,
            turnID: runtimeAction.turnID,
            method: runtimeAction.method,
            title: runtimeAction.title,
            detail: transcriptDetail,
            trace: sanitizedTrace,
            capturedAt: Date()
        )

        var entries = workerTraceByThreadID[threadID, default: []]
        entries.append(entry)
        if entries.count > 250 {
            entries.removeFirst(entries.count - 250)
        }
        workerTraceByThreadID[threadID] = entries

        let keyWithTurn = workerTraceFingerprint(
            threadID: threadID,
            turnID: runtimeAction.turnID,
            method: runtimeAction.method,
            title: runtimeAction.title,
            detail: transcriptDetail
        )
        workerTraceByActionFingerprint[keyWithTurn] = entry

        let keyWithoutTurn = workerTraceFingerprint(
            threadID: threadID,
            turnID: nil,
            method: runtimeAction.method,
            title: runtimeAction.title,
            detail: transcriptDetail
        )
        workerTraceByActionFingerprint[keyWithoutTurn] = entry

        persistWorkerTraceCacheSoon()
    }

    func workerTraceEntry(for action: ActionCard) -> WorkerTraceEntry? {
        let key = workerTraceFingerprint(
            threadID: action.threadID,
            turnID: nil,
            method: action.method,
            title: action.title,
            detail: action.detail
        )
        return workerTraceByActionFingerprint[key]
    }

    func presentWorkerTrace(for action: ActionCard) {
        guard let traceEntry = workerTraceEntry(for: action) else {
            return
        }
        activeWorkerTraceEntry = traceEntry
    }

    func dismissWorkerTraceSheet() {
        activeWorkerTraceEntry = nil
    }

    func restoreWorkerTraceCacheIfNeeded() async {
        guard let preferenceRepository else {
            workerTraceByThreadID = [:]
            workerTraceByActionFingerprint = [:]
            return
        }

        do {
            guard let raw = try await preferenceRepository.getPreference(key: .workerTraceCacheByTurn),
                  let data = raw.data(using: .utf8)
            else {
                workerTraceByThreadID = [:]
                workerTraceByActionFingerprint = [:]
                return
            }

            let payload = try JSONDecoder().decode(WorkerTraceCachePayload.self, from: data)
            var byThread: [UUID: [WorkerTraceEntry]] = [:]
            var byFingerprint: [String: WorkerTraceEntry] = [:]

            for persisted in payload.entries {
                let entry = WorkerTraceEntry(
                    threadID: persisted.threadID,
                    turnID: persisted.turnID,
                    method: persisted.method,
                    title: persisted.title,
                    detail: persisted.detail,
                    trace: persisted.trace,
                    capturedAt: persisted.capturedAt
                )
                byThread[persisted.threadID, default: []].append(entry)

                let methodDetailFingerprint = workerTraceFingerprint(
                    threadID: persisted.threadID,
                    turnID: persisted.turnID,
                    method: persisted.method,
                    title: persisted.title,
                    detail: persisted.detail
                )
                byFingerprint[methodDetailFingerprint] = entry

                let fallbackFingerprint = workerTraceFingerprint(
                    threadID: persisted.threadID,
                    turnID: nil,
                    method: persisted.method,
                    title: persisted.title,
                    detail: persisted.detail
                )
                byFingerprint[fallbackFingerprint] = entry
            }

            for (threadID, entries) in byThread {
                byThread[threadID] = Array(entries.sorted(by: { $0.capturedAt < $1.capturedAt }).suffix(250))
            }

            workerTraceByThreadID = byThread
            workerTraceByActionFingerprint = byFingerprint
        } catch {
            appendLog(.warning, "Failed restoring worker trace cache: \(error.localizedDescription)")
            workerTraceByThreadID = [:]
            workerTraceByActionFingerprint = [:]
        }
    }

    func workerTraceMarkdown(for entry: WorkerTraceEntry) -> String {
        let trace = entry.trace
        var lines: [String] = []

        lines.append("Worker: \(trace.workerID ?? "(unknown)")")
        lines.append("Role: \(trace.role ?? "(unspecified)")")
        lines.append("Status: \(trace.status ?? "(unknown)")")

        if let unavailableReason = trace.unavailableReason,
           !unavailableReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            lines.append("")
            lines.append("Trace status: \(unavailableReason)")
        }

        if let prompt = trace.prompt,
           !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            lines.append("")
            lines.append("## Worker Prompt")
            lines.append(prompt)
        }

        if let output = trace.output,
           !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            lines.append("")
            lines.append("## Worker Output")
            lines.append(output)
        }

        return lines.joined(separator: "\n")
    }

    private func persistWorkerTraceCacheSoon() {
        workerTracePersistenceTask?.cancel()
        workerTracePersistenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await persistWorkerTraceCache()
        }
    }

    private func persistWorkerTraceCache() async {
        guard let preferenceRepository else {
            return
        }

        let payload = WorkerTraceCachePayload(
            entries: Array(workerTraceByThreadID
                .flatMap { threadID, entries in
                    entries.map { entry in
                        PersistedWorkerTraceEntry(
                            threadID: threadID,
                            turnID: entry.turnID,
                            method: entry.method,
                            title: entry.title,
                            detail: entry.detail,
                            trace: entry.trace,
                            capturedAt: entry.capturedAt
                        )
                    }
                }
                .sorted(by: { $0.capturedAt < $1.capturedAt })
                .suffix(500))
        )

        do {
            let data = try JSONEncoder().encode(payload)
            guard let text = String(data: data, encoding: .utf8) else {
                return
            }
            try await preferenceRepository.setPreference(key: .workerTraceCacheByTurn, value: text)
        } catch {
            appendLog(.warning, "Failed persisting worker trace cache: \(error.localizedDescription)")
        }
    }

    private func sanitizeWorkerTrace(_ trace: RuntimeAction.WorkerTrace) -> RuntimeAction.WorkerTrace {
        RuntimeAction.WorkerTrace(
            workerID: trace.workerID.map(sanitizeLogText),
            role: trace.role.map(sanitizeLogText),
            prompt: trace.prompt.map(sanitizeLogText),
            output: trace.output.map(sanitizeLogText),
            status: trace.status.map(sanitizeLogText),
            unavailableReason: trace.unavailableReason.map(sanitizeLogText)
        )
    }

    private func workerTraceFingerprint(
        threadID: UUID,
        turnID: String?,
        method: String,
        title: String,
        detail: String
    ) -> String {
        [
            threadID.uuidString,
            turnID ?? "",
            method,
            title,
            sanitizeLogText(detail),
        ].joined(separator: "|")
    }
}

private struct WorkerTraceCachePayload: Codable {
    let entries: [PersistedWorkerTraceEntry]
}

private struct PersistedWorkerTraceEntry: Codable {
    let threadID: UUID
    let turnID: String?
    let method: String
    let title: String
    let detail: String
    let trace: RuntimeAction.WorkerTrace
    let capturedAt: Date
}
