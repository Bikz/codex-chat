import Foundation

public enum MemoryFileKind: String, CaseIterable, Hashable, Sendable, Codable {
    case profile
    case current
    case decisions
    case summaryLog = "summary-log"

    public var fileName: String {
        switch self {
        case .profile:
            return "profile.md"
        case .current:
            return "current.md"
        case .decisions:
            return "decisions.md"
        case .summaryLog:
            return "summary-log.md"
        }
    }

    public var displayName: String {
        switch self {
        case .profile:
            return "Profile"
        case .current:
            return "Current"
        case .decisions:
            return "Decisions"
        case .summaryLog:
            return "Summary Log"
        }
    }

    public var defaultContents: String {
        switch self {
        case .profile:
            return """
            # Profile

            Stable facts about the user/project that should rarely change.

            - Name:
            - Preferences:
            - Constraints:

            """
        case .current:
            return """
            # Current Context

            Active context the agent should consider for the next few turns.

            - What are we working on?
            - What's blocked?

            """
        case .decisions:
            return """
            # Decisions

            Record project decisions with dates and short rationale.

            - YYYY-MM-DD: ...

            """
        case .summaryLog:
            return """
            # Summary Log

            Auto-generated summaries appended after completed turns (if enabled).

            """
        }
    }
}

