import CodexChatCore
import Foundation

enum LiveActivityTraceFormatter {
    struct Presentation: Hashable {
        let statusLabel: String
        let showTraceBox: Bool
        let lines: [Line]
    }

    struct Line: Hashable, Identifiable {
        let id: UUID
        let text: String
    }

    static func buildPresentation(
        actions: [ActionCard],
        fallbackTitle: String,
        detailLevel: TranscriptDetailLevel
    ) -> Presentation {
        let statusLabel = statusLabelForLatestAction(actions: actions, fallbackTitle: fallbackTitle)
        guard !actions.isEmpty else {
            return Presentation(statusLabel: statusLabel, showTraceBox: false, lines: [])
        }

        if detailLevel == .detailed {
            return Presentation(
                statusLabel: statusLabel,
                showTraceBox: true,
                lines: actions.map(traceLine(for:))
            )
        }

        let hasRichTrace = actions.contains(where: hasRichTraceContent)
        guard hasRichTrace else {
            return Presentation(statusLabel: statusLabel, showTraceBox: false, lines: [])
        }

        let filtered = actions
            .filter { !isGenericLifecycleEvent($0) }
            .map(traceLine(for:))
        let lines = filtered.isEmpty ? actions.suffix(1).map(traceLine(for:)) : filtered

        return Presentation(statusLabel: statusLabel, showTraceBox: true, lines: lines)
    }

    private static func traceLine(for action: ActionCard) -> Line {
        let title = compactWhitespace(action.title)
        let detail = compactWhitespace(action.detail)
        let method = action.method.lowercased()

        let text: String = if detail.isEmpty || detail.caseInsensitiveCompare(title) == .orderedSame {
            title
        } else if method.contains("stderr")
            || method.contains("error")
            || method.contains("failed")
            || method.contains("terminated")
        {
            "\(title): \(compactDetail(detail, maxLength: 180))"
        } else {
            "\(title): \(compactDetail(detail, maxLength: 180))"
        }

        return Line(id: action.id, text: text)
    }

    private static func statusLabelForLatestAction(actions: [ActionCard], fallbackTitle: String) -> String {
        let fallback = compactWhitespace(fallbackTitle)
        guard let latest = actions.last else {
            return fallback.isEmpty ? "Working" : statusLabel(from: fallback)
        }

        let source = "\(latest.method) \(latest.title) \(latest.detail)"
        return statusLabel(from: source)
    }

    private static func statusLabel(from source: String) -> String {
        let lowered = source.lowercased()

        if lowered.contains("websearch") || lowered.contains("search") {
            return "Searching"
        }
        if lowered.contains("reasoning") || lowered.contains("think") {
            return "Thinking"
        }
        if lowered.contains("error")
            || lowered.contains("failed")
            || lowered.contains("stderr")
            || lowered.contains("terminated")
        {
            return "Troubleshooting"
        }
        if lowered.contains("commandexecution")
            || lowered.contains("command")
            || lowered.contains("shell")
            || lowered.contains("exec")
        {
            return "Running"
        }
        if lowered.contains("write")
            || lowered.contains("edit")
            || lowered.contains("patch")
            || lowered.contains("file")
        {
            return "Editing"
        }
        if lowered.contains("read") || lowered.contains("list") || lowered.contains("inspect") {
            return "Reading"
        }
        if lowered.contains("approval") {
            return "Waiting"
        }

        return "Working"
    }

    private static func hasRichTraceContent(_ action: ActionCard) -> Bool {
        let method = action.method.lowercased()
        if method.contains("stderr") || method.contains("command") {
            return true
        }

        let detail = compactWhitespace(action.detail)
        guard !detail.isEmpty else {
            return false
        }

        let title = compactWhitespace(action.title)
        if detail.caseInsensitiveCompare(title) == .orderedSame {
            return false
        }

        if isBoilerplateLifecycleText(detail.lowercased()) {
            return false
        }

        return true
    }

    private static func isGenericLifecycleEvent(_ action: ActionCard) -> Bool {
        let method = action.method.lowercased()
        if [
            "item/started",
            "item/completed",
            "turn/started",
            "turn/completed",
        ].contains(method) {
            return true
        }

        let title = compactWhitespace(action.title).lowercased()
        if isBoilerplateLifecycleText(title) {
            return true
        }

        let detail = compactWhitespace(action.detail).lowercased()
        if !detail.isEmpty, isBoilerplateLifecycleText(detail) {
            return true
        }

        return false
    }

    private static func isBoilerplateLifecycleText(_ value: String) -> Bool {
        value.hasPrefix("started ") || value.hasPrefix("completed ")
    }

    private static func compactWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compactDetail(_ value: String, maxLength: Int) -> String {
        let compacted = compactWhitespace(value)
        guard compacted.count > maxLength else {
            return compacted
        }
        return String(compacted.prefix(maxLength)) + "…"
    }
}
