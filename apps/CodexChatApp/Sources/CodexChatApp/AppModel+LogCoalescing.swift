import CodexKit
import Foundation

@MainActor
private var pendingThreadLogEntriesByModel: [ObjectIdentifier: [UUID: [ThreadLogEntry]]] = [:]

@MainActor
private var threadLogFlushTasksByModel: [ObjectIdentifier: Task<Void, Never>] = [:]

extension AppModel {
    @MainActor
    func enqueueThreadLog(level: LogLevel, text: String, to threadID: UUID) {
        let key = ObjectIdentifier(self)
        let sanitized = sanitizeLogText(text)
        var pendingByThread = pendingThreadLogEntriesByModel[key, default: [:]]
        pendingByThread[threadID, default: []].append(ThreadLogEntry(level: level, text: sanitized))
        pendingThreadLogEntriesByModel[key] = pendingByThread

        if threadLogFlushTasksByModel[key] != nil {
            return
        }

        threadLogFlushTasksByModel[key] = Task { [weak self] in
            guard let self else {
                pendingThreadLogEntriesByModel.removeValue(forKey: key)
                return
            }
            defer { threadLogFlushTasksByModel[key] = nil }
            try? await Task.sleep(nanoseconds: 33_000_000)
            guard !Task.isCancelled else { return }
            flushPendingThreadLogs()
        }
    }

    @MainActor
    private func flushPendingThreadLogs() {
        let key = ObjectIdentifier(self)
        let pendingByThread = pendingThreadLogEntriesByModel.removeValue(forKey: key) ?? [:]
        guard !pendingByThread.isEmpty else {
            return
        }

        for (threadID, entries) in pendingByThread {
            var logs = threadLogsByThreadID[threadID, default: []]
            logs.append(contentsOf: entries)
            if logs.count > 1000 {
                logs.removeFirst(logs.count - 1000)
            }
            threadLogsByThreadID[threadID] = logs
        }
    }
}
