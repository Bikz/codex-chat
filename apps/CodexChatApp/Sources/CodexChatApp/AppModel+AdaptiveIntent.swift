import CodexChatCore
import CodexKit
import Foundation

extension AppModel {
    enum AdaptiveIntent: Hashable {
        case desktopCleanup
        case calendarToday(rangeHours: Int)
        case remindersToday(rangeHours: Int)
        case messagesSend(recipient: String, body: String)
        case planRun(planPath: String?)
        case agentRoleSetup
    }

    func maybeHandleAdaptiveIntentFromComposer(
        text: String,
        attachments: [ComposerAttachment]
    ) -> Bool {
        guard attachments.isEmpty else {
            return false
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let intent = adaptiveIntent(for: trimmed),
              shouldAutoRouteAdaptiveIntent(intent)
        else {
            return false
        }

        Task {
            await executeAdaptiveIntent(intent, originalText: trimmed)
        }

        return true
    }

    private func shouldAutoRouteAdaptiveIntent(_ intent: AdaptiveIntent) -> Bool {
        guard areNativeComputerActionsEnabled else {
            return false
        }

        switch intent {
        case .desktopCleanup, .calendarToday, .remindersToday, .messagesSend:
            return true
        case .planRun, .agentRoleSetup:
            return false
        }
    }

    func triggerAdaptiveIntent(_ intent: AdaptiveIntent, originalText: String? = nil) {
        Task {
            await executeAdaptiveIntent(
                intent,
                originalText: originalText ?? defaultPrompt(for: intent)
            )
        }
    }

    func adaptiveIntent(for text: String) -> AdaptiveIntent? {
        let lowered = text.lowercased()

        if lowered.contains("clean up desktop")
            || lowered.contains("cleanup desktop")
            || lowered.contains("desktop cleanup")
            || lowered.contains("organize my desktop")
        {
            return .desktopCleanup
        }

        if containsCalendarKeyword(in: lowered),
           hasScheduleQueryCue(in: lowered, text: text)
        {
            return .calendarToday(rangeHours: parseRangeHours(text: text) ?? 24)
        }

        if containsRemindersKeyword(in: lowered),
           hasScheduleQueryCue(in: lowered, text: text)
        {
            return .remindersToday(rangeHours: parseRangeHours(text: text) ?? 24)
        }

        if let messageIntent = parseMessagesIntent(text: text) {
            return messageIntent
        }

        if lowered.contains("run plan") || lowered.contains("execute plan") || lowered.contains("plan run") {
            return .planRun(planPath: parsePlanPath(text: text))
        }

        if lowered.contains("agent role") || lowered.contains("role profile") || lowered.contains("agent profile") {
            return .agentRoleSetup
        }

        return nil
    }

    private func executeAdaptiveIntent(_ intent: AdaptiveIntent, originalText: String) async {
        do {
            let threadID = try await materializeDraftThreadIfNeeded()
            let project = try await resolveProjectContextForAdaptiveIntent(threadID: threadID)

            switch intent {
            case .desktopCleanup:
                try await runNativeComputerAction(
                    actionID: "desktop.cleanup",
                    arguments: [:],
                    threadID: threadID,
                    projectID: project.id
                )

            case let .calendarToday(rangeHours):
                let actionArguments = calendarActionArguments(text: originalText, defaultRangeHours: rangeHours)
                try await runNativeComputerAction(
                    actionID: "calendar.today",
                    arguments: actionArguments,
                    threadID: threadID,
                    projectID: project.id
                )

            case let .remindersToday(rangeHours):
                let actionArguments = remindersActionArguments(text: originalText, defaultRangeHours: rangeHours)
                try await runNativeComputerAction(
                    actionID: "reminders.today",
                    arguments: actionArguments,
                    threadID: threadID,
                    projectID: project.id
                )

            case let .messagesSend(recipient, body):
                try await runNativeComputerAction(
                    actionID: "messages.send",
                    arguments: [
                        "recipient": recipient,
                        "body": body,
                    ],
                    threadID: threadID,
                    projectID: project.id
                )

            case let .planRun(planPath):
                await preparePlanRunIntent(
                    threadID: threadID,
                    projectID: project.id,
                    planPath: planPath,
                    originalText: originalText
                )

            case .agentRoleSetup:
                await prepareAgentRoleBuilderIntent(
                    threadID: threadID,
                    originalText: originalText
                )
            }
        } catch {
            followUpStatusMessage = "Failed to handle adaptive action: \(error.localizedDescription)"
            appendLog(.error, "Adaptive intent failed: \(error.localizedDescription)")
        }
    }

    private func resolveProjectContextForAdaptiveIntent(threadID: UUID) async throws -> ProjectRecord {
        guard let threadRepository,
              let projectRepository
        else {
            throw CodexRuntimeError.invalidResponse("Project/thread repositories are unavailable.")
        }

        guard let thread = try await threadRepository.getThread(id: threadID) else {
            throw CodexChatCoreError.missingRecord(threadID.uuidString)
        }

        guard let project = try await projectRepository.getProject(id: thread.projectId) else {
            throw CodexChatCoreError.missingRecord(thread.projectId.uuidString)
        }

        return project
    }

    private func parseRangeHours(text: String) -> Int? {
        let pattern = #"next\s+(\d{1,3})\s+hours?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let fullRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange),
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Int(text[valueRange])
        else {
            return nil
        }

        return min(max(value, 1), 168)
    }

    private func parseRangeDays(text: String) -> Int? {
        let pattern = #"next\s+(\d{1,2})\s+days?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let fullRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange),
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Int(text[valueRange])
        else {
            return nil
        }

        return min(max(value, 1), 7)
    }

    private func parseRelativeDayOffset(in lowered: String) -> Int? {
        if lowered.contains("tomorrow")
            || lowered.contains("tmrw")
            || lowered.contains("tmr")
        {
            return 1
        }
        if lowered.contains("yesterday") {
            return -1
        }
        if lowered.contains("today") || lowered.contains("tonight") {
            return 0
        }
        return nil
    }

    private func containsCalendarKeyword(in lowered: String) -> Bool {
        if lowered.contains("calendar") {
            return true
        }

        return lowered.range(of: #"\bcal\b"#, options: .regularExpression) != nil
    }

    private func containsRemindersKeyword(in lowered: String) -> Bool {
        lowered.range(of: #"\breminders?\b"#, options: .regularExpression) != nil
    }

    private func hasScheduleQueryCue(in lowered: String, text: String) -> Bool {
        if parseRangeHours(text: text) != nil || parseRangeDays(text: text) != nil {
            return true
        }
        if parseRelativeDayOffset(in: lowered) != nil {
            return true
        }

        let cues = [
            "what's on",
            "whats on",
            "what do i have",
            "what do i got",
            "check my",
            "check",
            "show my",
            "show",
            "look at",
        ]

        return cues.contains(where: lowered.contains)
    }

    private func calendarActionArguments(text: String, defaultRangeHours: Int) -> [String: String] {
        let lowered = text.lowercased()
        let rangeHours = normalizedRangeHours(text: text, defaultRangeHours: defaultRangeHours)
        let dayOffset = parseRelativeDayOffset(in: lowered) ?? 0
        let anchor = shouldUseNowAnchor(loweredText: lowered, rangeHours: rangeHours, dayOffset: dayOffset) ? "now" : "dayStart"

        var arguments: [String: String] = [
            "rangeHours": String(rangeHours),
            "anchor": anchor,
        ]
        if dayOffset != 0 {
            arguments["dayOffset"] = String(dayOffset)
        }
        return arguments
    }

    private func remindersActionArguments(text: String, defaultRangeHours: Int) -> [String: String] {
        let lowered = text.lowercased()
        let rangeHours = normalizedRangeHours(text: text, defaultRangeHours: defaultRangeHours)
        let dayOffset = parseRelativeDayOffset(in: lowered) ?? 0
        let anchor = shouldUseNowAnchor(loweredText: lowered, rangeHours: rangeHours, dayOffset: dayOffset) ? "now" : "dayStart"

        var arguments: [String: String] = [
            "rangeHours": String(rangeHours),
            "anchor": anchor,
        ]
        if dayOffset != 0 {
            arguments["dayOffset"] = String(dayOffset)
        }
        return arguments
    }

    private func normalizedRangeHours(text: String, defaultRangeHours: Int) -> Int {
        if let parsedHours = parseRangeHours(text: text) {
            return min(max(parsedHours, 1), 168)
        }
        if let parsedDays = parseRangeDays(text: text) {
            return min(max(parsedDays * 24, 1), 168)
        }
        return min(max(defaultRangeHours, 1), 168)
    }

    private func shouldUseNowAnchor(loweredText: String, rangeHours: Int, dayOffset: Int) -> Bool {
        guard dayOffset == 0, rangeHours < 24 else {
            return false
        }

        return loweredText.contains("next")
            || loweredText.contains("in ")
            || loweredText.contains("hours")
    }

    private func parseMessagesIntent(text: String) -> AdaptiveIntent? {
        let patterns = [
            #"send\s+(?:a\s+)?message\s+to\s+(.+?)\s*[:,-]\s*(.+)$"#,
            #"(?:(?:can|could|would|will)\s+you\s+|please\s+)?send\s+(?:an?\s+)?(?:i\s*message|imessage|message|text|sms)\s+to\s+(.+?)\s*[:,-]\s*(.+)$"#,
            #"(?:(?:can|could|would|will)\s+you\s+|please\s+)?send\s+(?:an?\s+)?(?:i\s*message|imessage|message|text|sms)\s+to\s+(.+?)\s+(?:saying|that says|with(?:\s+the)?\s+message)\s+(.+)$"#,
            #"text\s+(.+?)\s+saying\s+(.+)$"#,
            #"(?:(?:can|could|would|will)\s+you\s+|please\s+)?text\s+(.+?)\s+saying\s+(.+)$"#,
            #"(?:(?:can|could|would|will)\s+you\s+|please\s+)?message\s+(.+?)\s*[:,-]\s*(.+)$"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let fullRange = NSRange(text.startIndex ..< text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: fullRange),
                  let recipientRange = Range(match.range(at: 1), in: text),
                  let bodyRange = Range(match.range(at: 2), in: text)
            else {
                continue
            }

            let recipient = stripEnclosingQuotes(
                in: text[recipientRange].trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let body = stripEnclosingQuotes(
                in: text[bodyRange].trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !recipient.isEmpty, !body.isEmpty else {
                continue
            }

            return .messagesSend(recipient: recipient, body: body)
        }

        return nil
    }

    private func stripEnclosingQuotes(in value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotePairs: [(Character, Character)] = [
            ("\"", "\""),
            ("'", "'"),
            ("“", "”"),
        ]

        for (start, end) in quotePairs where trimmed.first == start && trimmed.last == end && trimmed.count >= 2 {
            trimmed.removeFirst()
            trimmed.removeLast()
            return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private func parsePlanPath(text: String) -> String? {
        let pattern = #"([~/A-Za-z0-9_\-./]+\.md)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let fullRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange),
              let pathRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[pathRange])
    }

    private func defaultPrompt(for intent: AdaptiveIntent) -> String {
        switch intent {
        case .desktopCleanup:
            "Clean up desktop"
        case .calendarToday:
            "What's on my calendar today?"
        case .remindersToday:
            "What reminders do I have today?"
        case let .messagesSend(recipient, body):
            "Send message to \(recipient): \(body)"
        case let .planRun(planPath):
            if let planPath {
                "Run plan \(planPath)"
            } else {
                "Run plan"
            }
        case .agentRoleSetup:
            "Set up an agent role profile"
        }
    }

    private func preparePlanRunIntent(
        threadID: UUID,
        projectID: UUID,
        planPath: String?,
        originalText: String
    ) async {
        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: threadID,
                    method: "plan/run/requested",
                    title: "Plan run requested",
                    detail: "\(planPath ?? "No plan file provided")\n\n\(originalText)"
                )
            ),
            to: threadID
        )

        if let planPath {
            planRunnerSourcePath = planPath
        }
        openPlanRunnerSheet(pathHint: planPath)
        followUpStatusMessage = "Opened Plan Runner. Review the parsed plan and start execution."
        appendLog(.info, "Queued adaptive plan-run request for project \(projectID.uuidString)")
    }

    private func prepareAgentRoleBuilderIntent(threadID: UUID, originalText: String) async {
        let template = """
        Build a custom multi-agent role in `.codex/config.toml` and `.codex/agents/<role>.toml`.
        Requested intent:
        \(originalText)
        Include:
        1. `agents.<role>.description`
        2. `agents.<role>.config_file`
        3. Role template with model/reasoning/developer_instructions
        """

        appendEntry(
            .actionCard(
                ActionCard(
                    threadID: threadID,
                    method: "agent/role-builder/requested",
                    title: "Agent role setup requested",
                    detail: template
                )
            ),
            to: threadID
        )

        composerText = template
        followUpStatusMessage = "Prepared a role/profile setup template in the composer."
    }
}
