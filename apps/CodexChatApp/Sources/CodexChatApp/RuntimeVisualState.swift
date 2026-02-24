import CodexChatCore
import Foundation

enum RuntimeVisualStateKind: String, Hashable, Sendable {
    case reasoningActive
    case webSearchActive
    case fileReadActive
    case toolCallActive
    case commandExecActive
    case commandOutputStreaming
    case fileChangePreview
    case approvalRequired
    case approvalResolved
    case warningStderr
    case errorStderr
    case runtimeTerminated
    case turnCompletedSuccess
    case turnCompletedFailure
    case accountStateChanged
    case loginCompleted
    case lifecycleEvent
    case informational
}

enum RuntimeVisualStateTone: Hashable, Sendable {
    case neutral
    case accent
    case success
    case warning
    case error
}

struct RuntimeVisualStatePresentation: Hashable, Sendable {
    let kind: RuntimeVisualStateKind
    let label: String
    let iconName: String
    let tone: RuntimeVisualStateTone

    var isCritical: Bool {
        tone == .error
    }
}

enum RuntimeVisualStateClassifier {
    static func classify(_ action: ActionCard) -> RuntimeVisualStatePresentation {
        presentation(for: kind(for: action))
    }

    static func conciseTitle(for action: ActionCard) -> String {
        let title = compact(action.title)
        let state = classify(action)
        guard !title.isEmpty else { return state.label }

        let lowered = title.lowercased()
        if lowered.hasPrefix("started "), lowered.count > "started ".count {
            return "Started \(state.label)"
        }
        if lowered.hasPrefix("completed "), lowered.count > "completed ".count {
            return "Completed \(state.label)"
        }
        return title
    }

    static func detailPreview(for action: ActionCard, maxLength: Int = 220) -> String {
        let compacted = compact(action.detail)
        guard compacted.count > maxLength else {
            return compacted
        }
        return String(compacted.prefix(maxLength)) + "…"
    }

    static func statusLabel(for actions: [ActionCard], fallbackTitle: String) -> String {
        if let latest = actions.last {
            return statusLabel(for: kind(for: latest))
        }
        return statusLabelForFallbackText(fallbackTitle)
    }

    private static func kind(for action: ActionCard) -> RuntimeVisualStateKind {
        let method = action.method.lowercased()
        let title = compact(action.title).lowercased()
        let detail = compact(action.detail).lowercased()
        let itemType = normalizedItemType(for: action)

        if method == "runtime/terminated" {
            return .runtimeTerminated
        }

        if method == "runtime/stderr/coalesced" {
            return detail.contains("critical")
                || TranscriptActionPolicy.isCriticalStderr(action.detail)
                ? .errorStderr
                : .warningStderr
        }

        if method == "runtime/stderr" {
            return TranscriptActionPolicy.isCriticalStderr(action.detail) ? .errorStderr : .warningStderr
        }

        if method.contains("approval/reset") {
            return .approvalResolved
        }

        if method.contains("approval") || title.contains("approval") {
            return .approvalRequired
        }

        if method == "turn/completed" {
            return isFailureLike(text: "\(title) \(detail)")
                ? .turnCompletedFailure
                : .turnCompletedSuccess
        }

        if method == "turn/start/error" || method == "turn/error" {
            return .turnCompletedFailure
        }

        if method == "account/updated" {
            return .accountStateChanged
        }

        if method == "account/login/completed" {
            return .loginCompleted
        }

        if method.contains("commandexecution/outputdelta")
            || method.contains("command/output")
        {
            return .commandOutputStreaming
        }

        if let itemType {
            switch itemType {
            case "reasoning":
                return .reasoningActive
            case "websearch":
                return .webSearchActive
            case "commandexecution":
                return .commandExecActive
            case "filechange":
                return .fileChangePreview
            case "toolcall":
                return .toolCallActive
            case "fileread":
                return .fileReadActive
            default:
                break
            }
        }

        if method.contains("command")
            || title.contains("command")
            || title.contains("shell")
            || detail.contains("command")
        {
            return .commandExecActive
        }

        if method.contains("websearch")
            || title.contains("websearch")
            || title.contains(" search")
            || title.hasPrefix("search")
        {
            return .webSearchActive
        }

        if method.contains("read")
            || method.contains("list")
            || method.contains("inspect")
            || title.contains("read")
            || title.contains("list")
            || title.contains("inspect")
        {
            return .fileReadActive
        }

        if method.contains("tool")
            || title.contains("tool call")
            || detail.contains("\"tool\"")
        {
            return .toolCallActive
        }

        if method == "item/started"
            || method == "item/completed"
            || method == "turn/started"
        {
            return .lifecycleEvent
        }

        return .informational
    }

    private static func normalizedItemType(for action: ActionCard) -> String? {
        if let direct = action.itemType {
            let normalized = normalizeItemType(direct)
            if !normalized.isEmpty {
                return normalized
            }
        }

        let title = compact(action.title).lowercased()
        if title.hasPrefix("started ") {
            let raw = String(title.dropFirst("started ".count))
            let normalized = normalizeItemType(raw)
            if !normalized.isEmpty {
                return normalized
            }
        }
        if title.hasPrefix("completed ") {
            let raw = String(title.dropFirst("completed ".count))
            let normalized = normalizeItemType(raw)
            if !normalized.isEmpty {
                return normalized
            }
        }

        let pattern = #""type"\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let source = action.detail
        let range = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              match.numberOfRanges >= 2,
              let capture = Range(match.range(at: 1), in: source)
        else {
            return nil
        }

        let normalized = normalizeItemType(String(source[capture]))
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizeItemType(_ raw: String) -> String {
        let lowered = raw.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)

        switch lowered {
        case "read", "file", "fileread", "filereading", "list", "inspect":
            return "fileread"
        default:
            return lowered
        }
    }

    private static func isFailureLike(text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("error")
            || lowered.contains("failed")
            || lowered.contains("failure")
            || lowered.contains("cancel")
            || lowered.contains("terminated")
    }

    private static func statusLabel(for kind: RuntimeVisualStateKind) -> String {
        switch kind {
        case .reasoningActive:
            "Thinking"
        case .webSearchActive:
            "Searching"
        case .fileReadActive:
            "Reading"
        case .toolCallActive:
            "Calling tool"
        case .commandExecActive:
            "Running"
        case .commandOutputStreaming:
            "Streaming output"
        case .fileChangePreview:
            "Editing"
        case .approvalRequired:
            "Waiting for approval"
        case .approvalResolved:
            "Approval updated"
        case .warningStderr:
            "Warning"
        case .errorStderr:
            "Troubleshooting"
        case .runtimeTerminated:
            "Runtime stopped"
        case .turnCompletedSuccess:
            "Complete"
        case .turnCompletedFailure:
            "Failed"
        case .accountStateChanged, .loginCompleted:
            "Updating account"
        case .lifecycleEvent, .informational:
            "Working"
        }
    }

    private static func statusLabelForFallbackText(_ text: String) -> String {
        let lowered = text.lowercased()
        if lowered.contains("search") {
            return "Searching"
        }
        if lowered.contains("reason") || lowered.contains("think") {
            return "Thinking"
        }
        if lowered.contains("command") || lowered.contains("shell") || lowered.contains("exec") {
            return "Running"
        }
        if lowered.contains("read") || lowered.contains("list") || lowered.contains("inspect") {
            return "Reading"
        }
        if lowered.contains("error") || lowered.contains("failed") {
            return "Troubleshooting"
        }
        return "Working"
    }

    private static func presentation(for kind: RuntimeVisualStateKind) -> RuntimeVisualStatePresentation {
        switch kind {
        case .reasoningActive:
            RuntimeVisualStatePresentation(kind: kind, label: "Reasoning", iconName: "brain.head.profile", tone: .neutral)
        case .webSearchActive:
            RuntimeVisualStatePresentation(kind: kind, label: "Web search", iconName: "magnifyingglass", tone: .accent)
        case .fileReadActive:
            RuntimeVisualStatePresentation(kind: kind, label: "File read", iconName: "doc.text.magnifyingglass", tone: .neutral)
        case .toolCallActive:
            RuntimeVisualStatePresentation(kind: kind, label: "Tool call", iconName: "puzzlepiece.extension", tone: .accent)
        case .commandExecActive:
            RuntimeVisualStatePresentation(kind: kind, label: "Shell run", iconName: "terminal", tone: .accent)
        case .commandOutputStreaming:
            RuntimeVisualStatePresentation(kind: kind, label: "Command output", iconName: "text.alignleft", tone: .accent)
        case .fileChangePreview:
            RuntimeVisualStatePresentation(kind: kind, label: "File changes", iconName: "doc.badge.gearshape", tone: .accent)
        case .approvalRequired:
            RuntimeVisualStatePresentation(kind: kind, label: "Approval required", iconName: "hand.raised.fill", tone: .warning)
        case .approvalResolved:
            RuntimeVisualStatePresentation(kind: kind, label: "Approval reset", iconName: "checkmark.shield", tone: .warning)
        case .warningStderr:
            RuntimeVisualStatePresentation(kind: kind, label: "Runtime warning", iconName: "exclamationmark.triangle", tone: .warning)
        case .errorStderr:
            RuntimeVisualStatePresentation(kind: kind, label: "Runtime error", iconName: "xmark.octagon", tone: .error)
        case .runtimeTerminated:
            RuntimeVisualStatePresentation(kind: kind, label: "Runtime terminated", iconName: "bolt.slash", tone: .error)
        case .turnCompletedSuccess:
            RuntimeVisualStatePresentation(kind: kind, label: "Turn complete", iconName: "checkmark.circle", tone: .success)
        case .turnCompletedFailure:
            RuntimeVisualStatePresentation(kind: kind, label: "Turn failed", iconName: "exclamationmark.octagon", tone: .error)
        case .accountStateChanged:
            RuntimeVisualStatePresentation(kind: kind, label: "Account updated", iconName: "person.crop.circle.badge.checkmark", tone: .neutral)
        case .loginCompleted:
            RuntimeVisualStatePresentation(kind: kind, label: "Login event", iconName: "person.badge.key", tone: .neutral)
        case .lifecycleEvent:
            RuntimeVisualStatePresentation(kind: kind, label: "Lifecycle", iconName: "arrow.triangle.2.circlepath", tone: .neutral)
        case .informational:
            RuntimeVisualStatePresentation(kind: kind, label: "Event", iconName: "info.circle", tone: .neutral)
        }
    }

    private static func compact(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
