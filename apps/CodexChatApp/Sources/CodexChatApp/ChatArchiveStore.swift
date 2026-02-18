import CodexChatCore
import Foundation

enum ChatArchiveTurnStatus: String, Codable, Sendable {
    case pending
    case completed
    case failed
}

struct ArchivedTurnSummary: Hashable, Sendable {
    let turnID: UUID
    let timestamp: Date
    let status: ChatArchiveTurnStatus
    let userText: String
    let assistantText: String
    let actions: [ActionCard]

    init(
        turnID: UUID = UUID(),
        timestamp: Date,
        status: ChatArchiveTurnStatus = .completed,
        userText: String,
        assistantText: String,
        actions: [ActionCard]
    ) {
        self.turnID = turnID
        self.timestamp = timestamp
        self.status = status
        self.userText = userText
        self.assistantText = assistantText
        self.actions = actions
    }
}

enum ChatArchiveStore {
    private struct ArchivedActionPayload: Codable, Hashable {
        let title: String
        let method: String
        let detail: String
        let createdAt: Date

        init(action: ActionCard) {
            title = action.title
            method = action.method
            detail = action.detail
            createdAt = action.createdAt
        }

        var actionCard: ActionCard {
            ActionCard(
                threadID: UUID(),
                method: method,
                title: title,
                detail: detail,
                createdAt: createdAt
            )
        }
    }

    private static let formatVersionMarker = "<!-- CODEXCHAT_FORMAT_VERSION: 2 -->"
    private static let turnBeginMarker = "<!-- CODEXCHAT_TURN_BEGIN"
    private static let turnEndMarker = "<!-- CODEXCHAT_TURN_END -->"
    private static let pendingAssistantPlaceholder = "_Pending response..._"
    private static let failedAssistantPlaceholder = "_Turn failed before assistant output._"
    private static let legacyMigrationMarker = ".legacy-backfill-v1"

    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func formatISODate(_ date: Date) -> String {
        makeISOFormatter().string(from: date)
    }

    private static func parseISODate(_ value: String) -> Date? {
        makeISOFormatter().date(from: value)
    }

    static func beginCheckpoint(
        projectPath: String,
        threadID: UUID,
        turn: ArchivedTurnSummary
    ) throws -> URL {
        let pending = ArchivedTurnSummary(
            turnID: turn.turnID,
            timestamp: turn.timestamp,
            status: .pending,
            userText: turn.userText,
            assistantText: turn.assistantText,
            actions: turn.actions
        )
        return try upsertTurn(projectPath: projectPath, threadID: threadID, turn: pending)
    }

    static func finalizeCheckpoint(
        projectPath: String,
        threadID: UUID,
        turn: ArchivedTurnSummary
    ) throws -> URL {
        let normalized = ArchivedTurnSummary(
            turnID: turn.turnID,
            timestamp: turn.timestamp,
            status: .completed,
            userText: turn.userText,
            assistantText: turn.assistantText,
            actions: turn.actions
        )
        return try upsertTurn(projectPath: projectPath, threadID: threadID, turn: normalized)
    }

    static func failCheckpoint(
        projectPath: String,
        threadID: UUID,
        turn: ArchivedTurnSummary
    ) throws -> URL {
        let normalized = ArchivedTurnSummary(
            turnID: turn.turnID,
            timestamp: turn.timestamp,
            status: .failed,
            userText: turn.userText,
            assistantText: turn.assistantText,
            actions: turn.actions
        )
        return try upsertTurn(projectPath: projectPath, threadID: threadID, turn: normalized)
    }

    static func appendTurn(
        projectPath: String,
        threadID: UUID,
        turn: ArchivedTurnSummary
    ) throws -> URL {
        try finalizeCheckpoint(projectPath: projectPath, threadID: threadID, turn: turn)
    }

    static func loadRecentTurns(
        projectPath: String,
        threadID: UUID,
        limit: Int = 50
    ) throws -> [ArchivedTurnSummary] {
        let canonicalURL = canonicalThreadURL(projectPath: projectPath, threadID: threadID)
        let fileManager = FileManager.default

        let turns: [ArchivedTurnSummary]
        if fileManager.fileExists(atPath: canonicalURL.path) {
            let content = try String(contentsOf: canonicalURL, encoding: .utf8)
            turns = parseCanonicalTurns(content: content, threadID: threadID)
        } else {
            turns = try loadLegacyTurns(projectPath: projectPath, threadID: threadID)
        }

        let sorted = turns.sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            return $0.turnID.uuidString < $1.turnID.uuidString
        }

        if sorted.count <= limit {
            return sorted
        }

        return Array(sorted.suffix(limit))
    }

    static func latestArchiveURL(projectPath: String, threadID: UUID) -> URL? {
        let fileManager = FileManager.default
        let canonicalURL = canonicalThreadURL(projectPath: projectPath, threadID: threadID)
        if fileManager.fileExists(atPath: canonicalURL.path) {
            return canonicalURL
        }

        let chatsRoot = URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("chats", isDirectory: true)

        guard let enumerator = fileManager.enumerator(
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

            if url.path.contains("/chats/threads/") {
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

    static func migrateLegacyDateShardedArchivesIfNeeded(projectPath: String) throws -> Int {
        let markerURL = legacyMigrationMarkerURL(projectPath: projectPath)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: markerURL.path) {
            return 0
        }

        let chatsRoot = URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("chats", isDirectory: true)
        let canonicalRoot = chatsRoot.appendingPathComponent("threads", isDirectory: true)
        try fileManager.createDirectory(at: canonicalRoot, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: chatsRoot.path) else {
            try writeMigrationMarker(to: markerURL)
            return 0
        }

        let legacyFiles = try legacyArchiveFiles(projectPath: projectPath)
        guard !legacyFiles.isEmpty else {
            try writeMigrationMarker(to: markerURL)
            return 0
        }

        var legacyTurnsByThread: [UUID: [ArchivedTurnSummary]] = [:]
        for legacy in legacyFiles {
            let turns = try parseLegacyArchiveFile(url: legacy.url, threadID: legacy.threadID)
            legacyTurnsByThread[legacy.threadID, default: []].append(contentsOf: turns)
        }

        var insertedCount = 0

        for (threadID, legacyTurns) in legacyTurnsByThread {
            let canonicalURL = canonicalThreadURL(projectPath: projectPath, threadID: threadID)
            let existingTurns: [ArchivedTurnSummary]
            if fileManager.fileExists(atPath: canonicalURL.path) {
                let existingContent = try String(contentsOf: canonicalURL, encoding: .utf8)
                existingTurns = parseCanonicalTurns(content: existingContent, threadID: threadID)
            } else {
                existingTurns = []
            }

            let mergedTurns = dedupeTurns(existingTurns + legacyTurns)
                .sorted {
                    if $0.timestamp != $1.timestamp {
                        return $0.timestamp < $1.timestamp
                    }
                    return $0.turnID.uuidString < $1.turnID.uuidString
                }

            let additions = max(0, mergedTurns.count - existingTurns.count)
            if additions > 0 || !fileManager.fileExists(atPath: canonicalURL.path) {
                try overwriteCanonicalTurns(projectPath: projectPath, threadID: threadID, turns: mergedTurns)
            }
            insertedCount += additions
        }

        try writeMigrationMarker(to: markerURL)
        return insertedCount
    }

    private static func upsertTurn(
        projectPath: String,
        threadID: UUID,
        turn: ArchivedTurnSummary
    ) throws -> URL {
        let archiveURL = canonicalThreadURL(projectPath: projectPath, threadID: threadID)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let existingText: String = if fileManager.fileExists(atPath: archiveURL.path) {
            try String(contentsOf: archiveURL, encoding: .utf8)
        } else {
            canonicalHeader(threadID: threadID)
        }

        let block = renderTurnBlock(turn)
        var updatedText = existingText

        if let range = blockRange(for: turn.turnID, in: existingText) {
            updatedText.replaceSubrange(range, with: block)
        } else {
            if !updatedText.hasSuffix("\n\n") {
                updatedText += "\n\n"
            }
            updatedText += block
        }

        try writeAtomically(text: updatedText, to: archiveURL)
        return archiveURL
    }

    private static func overwriteCanonicalTurns(
        projectPath: String,
        threadID: UUID,
        turns: [ArchivedTurnSummary]
    ) throws {
        let archiveURL = canonicalThreadURL(projectPath: projectPath, threadID: threadID)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var content = canonicalHeader(threadID: threadID)
        if !turns.isEmpty {
            content += "\n"
        }

        for turn in turns {
            content += renderTurnBlock(turn)
        }

        try writeAtomically(text: content, to: archiveURL)
    }

    private static func canonicalHeader(threadID: UUID) -> String {
        """
        # Thread Transcript for \(threadID.uuidString)

        \(formatVersionMarker)
        """
    }

    private static func renderTurnBlock(_ turn: ArchivedTurnSummary) -> String {
        let timestamp = formatISODate(turn.timestamp)
        let user = turn.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        var assistant = turn.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if assistant.isEmpty {
            switch turn.status {
            case .pending:
                assistant = pendingAssistantPlaceholder
            case .failed:
                assistant = failedAssistantPlaceholder
            case .completed:
                assistant = "_No assistant output captured._"
            }
        }

        let actionsJSON = renderActionsJSON(turn.actions)

        return """
        <!-- CODEXCHAT_TURN_BEGIN id=\(turn.turnID.uuidString) timestamp=\(timestamp) status=\(turn.status.rawValue) -->
        ## Turn \(timestamp)

        ### User

        \(user)

        ### Assistant

        \(assistant)

        ### Actions

        ```json
        \(actionsJSON)
        ```

        \(turnEndMarker)

        ---

        """
    }

    private static func renderActionsJSON(_ actions: [ActionCard]) -> String {
        let payload = actions.map(ArchivedActionPayload.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return json
    }

    private static func parseCanonicalTurns(content: String, threadID: UUID) -> [ArchivedTurnSummary] {
        var results: [ArchivedTurnSummary] = []
        var cursor = content.startIndex

        while let beginRange = content.range(of: turnBeginMarker, range: cursor ..< content.endIndex) {
            guard let markerLineEnd = content[beginRange.lowerBound...].firstIndex(of: "\n") else {
                break
            }

            let markerLine = String(content[beginRange.lowerBound ..< markerLineEnd])
            guard let metadata = parseTurnMetadata(markerLine),
                  let endRange = content.range(of: turnEndMarker, range: markerLineEnd ..< content.endIndex)
            else {
                break
            }

            let blockBody = String(content[markerLineEnd ..< endRange.lowerBound])
            let userText = extractSection(named: "### User", nextHeading: "### Assistant", in: blockBody) ?? ""
            let assistantRaw = extractSection(named: "### Assistant", nextHeading: "### Actions", in: blockBody) ?? ""
            let actionsRaw = extractSection(named: "### Actions", nextHeading: nil, in: blockBody) ?? ""
            let actions = parseActionsSection(actionsRaw, threadID: threadID, timestamp: metadata.timestamp)

            let assistantText: String = if assistantRaw == pendingAssistantPlaceholder ||
                assistantRaw == failedAssistantPlaceholder ||
                assistantRaw == "_No assistant output captured._"
            {
                ""
            } else {
                assistantRaw
            }

            results.append(
                ArchivedTurnSummary(
                    turnID: metadata.turnID,
                    timestamp: metadata.timestamp,
                    status: metadata.status,
                    userText: userText,
                    assistantText: assistantText,
                    actions: actions
                )
            )

            cursor = endRange.upperBound
        }

        return results
    }

    private static func parseActionsSection(
        _ section: String,
        threadID: UUID,
        timestamp _: Date
    ) -> [ActionCard] {
        let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let json: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 2 {
                json = lines.dropFirst().dropLast().joined(separator: "\n")
            } else {
                json = "[]"
            }
        } else {
            json = trimmed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = json.data(using: .utf8),
              let payload = try? decoder.decode([ArchivedActionPayload].self, from: data)
        else {
            return []
        }

        return payload.map { item in
            ActionCard(
                threadID: threadID,
                method: item.method,
                title: item.title,
                detail: item.detail,
                createdAt: item.createdAt
            )
        }
    }

    private static func parseTurnMetadata(_ markerLine: String) -> (turnID: UUID, timestamp: Date, status: ChatArchiveTurnStatus)? {
        guard markerLine.hasPrefix("<!-- CODEXCHAT_TURN_BEGIN"),
              markerLine.hasSuffix("-->")
        else {
            return nil
        }

        var normalized = markerLine
            .replacingOccurrences(of: "<!-- CODEXCHAT_TURN_BEGIN", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.hasPrefix("id=") == false {
            normalized = normalized.replacingOccurrences(of: "  ", with: " ")
        }

        let components = normalized
            .split(separator: " ")
            .map(String.init)

        var values: [String: String] = [:]
        for component in components {
            let parts = component.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            values[parts[0]] = parts[1]
        }

        guard let turnIDRaw = values["id"],
              let turnID = UUID(uuidString: turnIDRaw),
              let timestampRaw = values["timestamp"],
              let timestamp = parseISODate(timestampRaw)
        else {
            return nil
        }

        let status = ChatArchiveTurnStatus(rawValue: values["status"] ?? "completed") ?? .completed
        return (turnID, timestamp, status)
    }

    private static func extractSection(named heading: String, nextHeading: String?, in text: String) -> String? {
        let marker = "\(heading)\n\n"
        guard let startRange = text.range(of: marker) else {
            return nil
        }

        let contentStart = startRange.upperBound
        let contentEnd: String.Index = if let nextHeading,
                                          let nextRange = text.range(of: "\n\n\(nextHeading)\n\n", range: contentStart ..< text.endIndex)
        {
            nextRange.lowerBound
        } else {
            text.endIndex
        }

        return String(text[contentStart ..< contentEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func blockRange(for turnID: UUID, in text: String) -> Range<String.Index>? {
        let beginPrefix = "\(turnBeginMarker) id=\(turnID.uuidString) "
        guard let beginRange = text.range(of: beginPrefix) else {
            return nil
        }

        guard let endRange = text.range(of: turnEndMarker, range: beginRange.lowerBound ..< text.endIndex) else {
            return nil
        }

        var end = endRange.upperBound
        let trailingOptions = ["\n\n---\n\n", "\n---\n\n", "\n\n---\n", "\n---\n"]
        for trailing in trailingOptions where text[end...].hasPrefix(trailing) {
            end = text.index(end, offsetBy: trailing.count)
            break
        }

        return beginRange.lowerBound ..< end
    }

    private static func writeAtomically(text: String, to url: URL) throws {
        let fileManager = FileManager.default
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).tmp-\(UUID().uuidString)", isDirectory: false)

        do {
            try Data(text.utf8).write(to: tempURL, options: [.atomic])
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(
                    url,
                    withItemAt: tempURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try fileManager.moveItem(at: tempURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    private static func canonicalThreadURL(projectPath: String, threadID: UUID) -> URL {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)
            .appendingPathComponent("\(threadID.uuidString).md", isDirectory: false)
    }

    private static func legacyMigrationMarkerURL(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)
            .appendingPathComponent(legacyMigrationMarker, isDirectory: false)
    }

    private static func writeMigrationMarker(to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = "Backfilled at \(formatISODate(Date()))\n"
        try writeAtomically(text: text, to: url)
    }

    private static func dedupeTurns(_ turns: [ArchivedTurnSummary]) -> [ArchivedTurnSummary] {
        var seen: Set<String> = []
        var results: [ArchivedTurnSummary] = []

        for turn in turns {
            let fingerprint = turnFingerprint(turn)
            if seen.contains(fingerprint) {
                continue
            }
            seen.insert(fingerprint)
            results.append(turn)
        }

        return results
    }

    private static func turnFingerprint(_ turn: ArchivedTurnSummary) -> String {
        let actions = turn.actions
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                if lhs.method != rhs.method {
                    return lhs.method < rhs.method
                }
                if lhs.title != rhs.title {
                    return lhs.title < rhs.title
                }
                return lhs.detail < rhs.detail
            }
            .map { action in
                "\(formatISODate(action.createdAt))|\(action.title)|\(action.method)|\(action.detail)"
            }
            .joined(separator: "||")

        return "\(formatISODate(turn.timestamp))\n\(turn.status.rawValue)\n\(turn.userText)\n\(turn.assistantText)\n\(actions)"
    }

    private static func legacyArchiveFiles(projectPath: String) throws -> [(threadID: UUID, url: URL)] {
        let chatsRoot = URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("chats", isDirectory: true)
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: chatsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(threadID: UUID, url: URL)] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "md" else {
                continue
            }

            if url.path.contains("/chats/threads/") {
                continue
            }

            let fileName = url.deletingPathExtension().lastPathComponent
            guard let threadID = UUID(uuidString: fileName) else {
                continue
            }

            files.append((threadID, url))
        }

        return files
    }

    private static func loadLegacyTurns(projectPath: String, threadID: UUID) throws -> [ArchivedTurnSummary] {
        let legacyFiles = try legacyArchiveFiles(projectPath: projectPath)
            .filter { $0.threadID == threadID }
            .map(\.url)

        var turns: [ArchivedTurnSummary] = []
        for url in legacyFiles {
            try turns.append(contentsOf: parseLegacyArchiveFile(url: url, threadID: threadID))
        }

        return dedupeTurns(turns)
    }

    private static func parseLegacyArchiveFile(url: URL, threadID: UUID) throws -> [ArchivedTurnSummary] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let chunks = content.components(separatedBy: "\n## Turn ")
        guard chunks.count > 1 else {
            return []
        }

        var turns: [ArchivedTurnSummary] = []

        for chunk in chunks.dropFirst() {
            guard let firstNewline = chunk.firstIndex(of: "\n") else {
                continue
            }

            let timestampRaw = String(chunk[..<firstNewline]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let timestamp = parseISODate(timestampRaw) else {
                continue
            }

            let body = String(chunk[firstNewline...])
            let userText = extractLegacySection(named: "### User", nextHeading: "### Assistant", in: body) ?? ""
            let assistantText = extractLegacySection(named: "### Assistant", nextHeading: "### Actions", in: body) ?? ""
            let actionsText = extractLegacySection(named: "### Actions", nextHeading: nil, in: body) ?? ""
            let actions = parseLegacyActions(from: actionsText, threadID: threadID, timestamp: timestamp)

            turns.append(
                ArchivedTurnSummary(
                    timestamp: timestamp,
                    status: .completed,
                    userText: userText,
                    assistantText: assistantText,
                    actions: actions
                )
            )
        }

        return turns
    }

    private static func extractLegacySection(named heading: String, nextHeading: String?, in text: String) -> String? {
        guard let markerRange = text.range(of: "\(heading)\n\n") else {
            return nil
        }

        let contentStart = markerRange.upperBound
        let contentEnd: String.Index = if let nextHeading,
                                          let nextRange = text.range(of: "\n\n\(nextHeading)\n\n", range: contentStart ..< text.endIndex)
        {
            nextRange.lowerBound
        } else if let dividerRange = text.range(of: "\n\n---", range: contentStart ..< text.endIndex) {
            dividerRange.lowerBound
        } else {
            text.endIndex
        }

        return String(text[contentStart ..< contentEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseLegacyActions(
        from section: String,
        threadID: UUID,
        timestamp: Date
    ) -> [ActionCard] {
        let lines = section
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let pattern = #"^- \*\*(.+)\*\* \(`([^`]+)`\): (.*)$"#
        let regex = try? NSRegularExpression(pattern: pattern)

        var actions: [ActionCard] = []

        for line in lines {
            guard let regex,
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges == 4,
                  let titleRange = Range(match.range(at: 1), in: line),
                  let methodRange = Range(match.range(at: 2), in: line),
                  let detailRange = Range(match.range(at: 3), in: line)
            else {
                continue
            }

            actions.append(
                ActionCard(
                    threadID: threadID,
                    method: String(line[methodRange]),
                    title: String(line[titleRange]),
                    detail: String(line[detailRange]),
                    createdAt: timestamp
                )
            )
        }

        return actions
    }
}
