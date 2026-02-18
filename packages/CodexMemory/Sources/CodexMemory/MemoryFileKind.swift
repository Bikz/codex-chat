import Foundation

public enum MemoryFileKind: String, CaseIterable, Hashable, Sendable, Codable {
    case profile
    case current
    case decisions
    case summaryLog = "summary-log"

    public var fileName: String {
        switch self {
        case .profile:
            "profile.md"
        case .current:
            "current.md"
        case .decisions:
            "decisions.md"
        case .summaryLog:
            "summary-log.md"
        }
    }

    public var displayName: String {
        switch self {
        case .profile:
            "Profile"
        case .current:
            "Current"
        case .decisions:
            "Decisions"
        case .summaryLog:
            "Summary Log"
        }
    }

    public var defaultContents: String {
        switch self {
        case .profile:
            """
            # Profile

            Stable facts about the user/project that should rarely change.

            - Name:
            - Preferences:
            - Constraints:

            """
        case .current:
            """
            # Current Context

            Active context the agent should consider for the next few turns.

            - What are we working on?
            - What's blocked?

            """
        case .decisions:
            """
            # Decisions

            Record project decisions with dates and short rationale.

            - YYYY-MM-DD: ...

            """
        case .summaryLog:
            """
            # Summary Log

            Auto-generated summaries appended after completed turns (if enabled).

            """
        }
    }
}
