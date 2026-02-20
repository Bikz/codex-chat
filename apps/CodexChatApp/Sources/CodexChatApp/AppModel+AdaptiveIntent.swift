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

        if let scheduleIntent = parseScheduleAdaptiveIntent(text: text) {
            return scheduleIntent
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

    private func parseScheduleAdaptiveIntent(text: String) -> AdaptiveIntent? {
        let preferredDomain = preferredScheduleDomainForFollowUp()
        guard let query = ScheduleQueryParser.parse(
            text: text,
            preferredDomain: preferredDomain
        ) else {
            return nil
        }

        switch query.domain {
        case .calendar:
            return .calendarToday(rangeHours: query.rangeHours)
        case .reminders:
            return .remindersToday(rangeHours: query.rangeHours)
        }
    }

    private func preferredScheduleDomainForFollowUp() -> ScheduleQueryParser.Domain? {
        guard let threadID = selectedThreadID else {
            return nil
        }
        return preferredScheduleDomain(in: transcriptStore[threadID, default: []])
    }

    private func preferredScheduleDomain(in entries: [TranscriptEntry]) -> ScheduleQueryParser.Domain? {
        for entry in entries.reversed() {
            guard case let .message(message) = entry,
                  message.role == .user
            else {
                continue
            }

            if let domain = ScheduleQueryParser.detectDomain(in: message.text.lowercased()) {
                return domain
            }
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

    private func calendarActionArguments(text: String, defaultRangeHours: Int) -> [String: String] {
        scheduleActionArguments(
            text: text,
            defaultRangeHours: defaultRangeHours,
            preferredDomain: .calendar
        )
    }

    private func remindersActionArguments(text: String, defaultRangeHours: Int) -> [String: String] {
        scheduleActionArguments(
            text: text,
            defaultRangeHours: defaultRangeHours,
            preferredDomain: .reminders
        )
    }

    private func scheduleActionArguments(
        text: String,
        defaultRangeHours: Int,
        preferredDomain: ScheduleQueryParser.Domain
    ) -> [String: String] {
        if let parsed = ScheduleQueryParser.parse(
            text: text,
            preferredDomain: preferredDomain
        ) {
            return parsed.actionArguments(queryText: text)
        }

        var arguments: [String: String] = [
            "rangeHours": String(min(max(defaultRangeHours, 1), 168)),
            "anchor": ScheduleQueryParser.Anchor.dayStart.rawValue,
        ]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            arguments["queryText"] = trimmed
        }
        return arguments
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
