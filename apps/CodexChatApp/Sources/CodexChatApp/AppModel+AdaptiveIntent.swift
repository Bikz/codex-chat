import CodexChatCore
import CodexKit
import Foundation

extension AppModel {
    enum AdaptiveIntent: Hashable {
        case desktopCleanup
        case calendarToday(rangeHours: Int)
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
              let intent = adaptiveIntent(for: trimmed)
        else {
            return false
        }

        Task {
            await executeAdaptiveIntent(intent, originalText: trimmed)
        }

        return true
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

        if lowered.contains("calendar"),
           lowered.contains("today") || lowered.contains("what's on") || lowered.contains("whats on")
        {
            return .calendarToday(rangeHours: parseRangeHours(text: text) ?? 24)
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
                try await runNativeComputerAction(
                    actionID: "calendar.today",
                    arguments: ["rangeHours": String(rangeHours)],
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

    private func parseMessagesIntent(text: String) -> AdaptiveIntent? {
        let patterns = [
            #"send\s+(?:a\s+)?message\s+to\s+(.+?)\s*[:,-]\s*(.+)$"#,
            #"text\s+(.+?)\s+saying\s+(.+)$"#,
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

            let recipient = text[recipientRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let body = text[bodyRange].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recipient.isEmpty, !body.isEmpty else {
                continue
            }

            return .messagesSend(recipient: recipient, body: body)
        }

        return nil
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

        followUpStatusMessage = "Plan run routing is ready. Use the upcoming Plan Runner sheet to execute dependencies."
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
