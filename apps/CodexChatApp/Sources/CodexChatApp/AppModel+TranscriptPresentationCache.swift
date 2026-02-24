import CodexChatCore
import Foundation

struct TranscriptPresentationCacheKey: Hashable {
    let threadID: UUID
    let detailLevel: TranscriptDetailLevel
    let transcriptRevision: UInt64
    let activeTurnID: UUID?
    let activeAssistantLength: Int
    let activeActionCount: Int
    let threadLogCount: Int
    let threadLogTailSignature: Int
}

struct TranscriptPresentationCacheEntry {
    let rows: [TranscriptPresentationRow]
    let timestamp: Date
}

extension AppModel {
    private static let transcriptPresentationCacheLimit = 8

    func bumpTranscriptRevision(for threadID: UUID) {
        transcriptRevisionsByThreadID[threadID] = (transcriptRevisionsByThreadID[threadID] ?? 0) &+ 1
        transcriptPresentationCache = transcriptPresentationCache.filter { $0.key.threadID != threadID }
        transcriptPresentationCacheLRU.removeAll { $0.threadID == threadID }
    }

    func presentationRowsForSelectedConversation(entries: [TranscriptEntry]) -> [TranscriptPresentationRow] {
        guard let selectedThreadID else {
            return TranscriptPresentationBuilder.rows(
                entries: entries,
                detailLevel: transcriptDetailLevel,
                activeTurnContext: activeTurnContextForSelectedThread,
                threadLogs: []
            )
        }

        let activeContext = activeTurnContextForSelectedThread
        let threadLogs = threadLogsByThreadID[selectedThreadID, default: []]
        let cacheKey = TranscriptPresentationCacheKey(
            threadID: selectedThreadID,
            detailLevel: transcriptDetailLevel,
            transcriptRevision: transcriptRevisionsByThreadID[selectedThreadID] ?? 0,
            activeTurnID: activeContext?.localTurnID,
            activeAssistantLength: activeContext?.assistantText.count ?? 0,
            activeActionCount: activeContext?.actions.count ?? 0,
            threadLogCount: threadLogs.count,
            threadLogTailSignature: threadLogTailSignature(for: threadLogs)
        )

        if let cached = transcriptPresentationCache[cacheKey] {
            touchTranscriptPresentationCacheKey(cacheKey)
            return cached.rows
        }

        let rows = TranscriptPresentationBuilder.rows(
            entries: entries,
            detailLevel: transcriptDetailLevel,
            activeTurnContext: activeContext,
            threadLogs: threadLogs
        )
        transcriptPresentationCache[cacheKey] = TranscriptPresentationCacheEntry(rows: rows, timestamp: Date())
        touchTranscriptPresentationCacheKey(cacheKey)
        enforceTranscriptPresentationCacheLimit()
        return rows
    }

    private func touchTranscriptPresentationCacheKey(_ key: TranscriptPresentationCacheKey) {
        transcriptPresentationCacheLRU.removeAll { $0 == key }
        transcriptPresentationCacheLRU.append(key)
    }

    private func enforceTranscriptPresentationCacheLimit() {
        while transcriptPresentationCacheLRU.count > Self.transcriptPresentationCacheLimit {
            let oldestKey = transcriptPresentationCacheLRU.removeFirst()
            transcriptPresentationCache.removeValue(forKey: oldestKey)
        }
    }

    private func threadLogTailSignature(for threadLogs: [ThreadLogEntry]) -> Int {
        var hasher = Hasher()
        for entry in threadLogs.suffix(12) {
            hasher.combine(entry.id)
            hasher.combine(entry.timestamp.timeIntervalSinceReferenceDate)
            hasher.combine(entry.level.rawValue)
            hasher.combine(entry.text)
        }
        return hasher.finalize()
    }
}
