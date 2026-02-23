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
        let visibleActions = actions.filter { action in
            !TranscriptActionPolicy.shouldSuppressFromTranscript(action)
        }
        let statusLabel = RuntimeVisualStateClassifier.statusLabel(
            for: visibleActions,
            fallbackTitle: fallbackTitle
        )
        guard !visibleActions.isEmpty else {
            return Presentation(statusLabel: statusLabel, showTraceBox: false, lines: [])
        }

        if detailLevel == .detailed {
            return Presentation(
                statusLabel: statusLabel,
                showTraceBox: true,
                lines: visibleActions.map(traceLine(for:))
            )
        }

        let hasRichTrace = visibleActions.contains(where: hasRichTraceContent)
        guard hasRichTrace else {
            return Presentation(statusLabel: statusLabel, showTraceBox: false, lines: [])
        }

        let filtered = visibleActions
            .filter { !isGenericLifecycleEvent($0) }
            .map(traceLine(for:))
        let lines = filtered.isEmpty ? visibleActions.suffix(1).map(traceLine(for:)) : filtered

        return Presentation(statusLabel: statusLabel, showTraceBox: true, lines: lines)
    }

    private static func traceLine(for action: ActionCard) -> Line {
        let title = RuntimeVisualStateClassifier.conciseTitle(for: action)
        let detail = compactWhitespace(action.detail)
        let stateLabel = RuntimeVisualStateClassifier.classify(action).label

        let text: String = if detail.isEmpty || detail.caseInsensitiveCompare(title) == .orderedSame {
            title
        } else {
            "\(stateLabel): \(compactDetail(detail, maxLength: 180))"
        }

        return Line(id: action.id, text: text)
    }

    private static func hasRichTraceContent(_ action: ActionCard) -> Bool {
        let state = RuntimeVisualStateClassifier.classify(action).kind
        if state == .commandExecActive
            || state == .commandOutputStreaming
            || state == .warningStderr
            || state == .errorStderr
            || state == .runtimeTerminated
            || state == .approvalRequired
        {
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
