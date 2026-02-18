import CodexChatCore
import Foundation

struct ArchivedTurnSummary {
    let timestamp: Date
    let userText: String
    let assistantText: String
    let actions: [ActionCard]
}

enum ChatArchiveStore {
    static func appendTurn(
        projectPath: String,
        threadID: UUID,
        turn: ArchivedTurnSummary
    ) throws -> URL {
        let fileManager = FileManager.default
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let threadDirectory = URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent(dayFormatter.string(from: turn.timestamp), isDirectory: true)

        try fileManager.createDirectory(at: threadDirectory, withIntermediateDirectories: true)

        let archiveURL = threadDirectory.appendingPathComponent("\(threadID.uuidString).md")
        if !fileManager.fileExists(atPath: archiveURL.path) {
            let header = "# Chat Archive for \(threadID.uuidString)\n\n"
            let data = Data(header.utf8)
            try data.write(to: archiveURL, options: [.atomic])
        }

        var block = "## Turn \(turn.timestamp.formatted(.dateTime.year().month().day().hour().minute().second()))\n\n"
        block += "### User\n\n"
        block += turn.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        block += "\n\n"
        block += "### Assistant\n\n"

        let assistantBody = turn.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        block += assistantBody.isEmpty ? "_No assistant output captured._" : assistantBody
        block += "\n\n"

        if !turn.actions.isEmpty {
            block += "### Actions\n\n"
            for action in turn.actions {
                block += "- **\(action.title)** (`\(action.method)`): \(collapsed(action.detail))\n"
            }
            block += "\n"
        }

        block += "---\n\n"

        let handle = try FileHandle(forWritingTo: archiveURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = block.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }

        return archiveURL
    }

    static func latestArchiveURL(projectPath: String, threadID: UUID) -> URL? {
        let chatsRoot = URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("chats", isDirectory: true)

        guard let enumerator = FileManager.default.enumerator(
            at: chatsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let expectedFileName = "\(threadID.uuidString).md"
        var best: (url: URL, date: Date)?

        for case let url as URL in enumerator {
            guard url.lastPathComponent == expectedFileName else {
                continue
            }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = values?.contentModificationDate ?? .distantPast

            if let bestDate = best?.date, bestDate >= modified {
                continue
            }
            best = (url, modified)
        }

        return best?.url
    }

    private static func collapsed(_ text: String, limit: Int = 160) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard compact.count > limit else {
            return compact
        }

        return String(compact.prefix(limit - 1)) + "…"
    }
}
