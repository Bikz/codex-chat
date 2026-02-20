import CodexChatCore
import Foundation

enum TranscriptPresentationRow: Identifiable, Hashable {
    case message(ChatMessage)
    case action(ActionCard)
    case liveActivity(LiveTurnActivityPresentation)
    case turnSummary(TurnSummaryPresentation)

    var id: String {
        switch self {
        case let .message(message):
            "message:\(message.id.uuidString)"
        case let .action(action):
            "action:\(action.id.uuidString)"
        case let .liveActivity(activity):
            "live-activity:\(activity.id.uuidString)"
        case let .turnSummary(summary):
            "turn-summary:\(summary.id.uuidString)"
        }
    }
}

struct TranscriptMilestoneCounts: Hashable {
    var reasoning = 0
    var commandExecution = 0
    var warnings = 0
    var errors = 0

    var hasAny: Bool {
        reasoning > 0 || commandExecution > 0 || warnings > 0 || errors > 0
    }
}

struct LiveTurnActivityPresentation: Identifiable, Hashable {
    let id: UUID
    let turnID: UUID
    let userPreview: String
    let assistantPreview: String
    let latestActionTitle: String
    let actions: [ActionCard]
    let milestoneCounts: TranscriptMilestoneCounts
}

struct TurnSummaryPresentation: Identifiable, Hashable {
    let id: UUID
    let actions: [ActionCard]
    let actionCount: Int
    let hiddenActionCount: Int
    let milestoneCounts: TranscriptMilestoneCounts
    let isFailure: Bool
}

enum TranscriptActionClassification: Hashable {
    case critical
    case lifecycleNoise
    case milestone
    case stderr
    case informational
}

enum TranscriptActionPolicy {
    static func classify(
        method: String,
        title: String,
        detail: String,
        itemType: String? = nil
    ) -> TranscriptActionClassification {
        let methodLower = method.lowercased()
        let titleLower = title.lowercased()
        let detailLower = detail.lowercased()
        let itemTypeLower = itemType?.lowercased() ?? ""

        if methodLower == "runtime/stderr" {
            if isKnownSkillLoaderStderrNoise(detail) {
                return .lifecycleNoise
            }
            return .stderr
        }

        if [
            "item/started",
            "item/completed",
            "turn/started",
            "turn/completed",
        ].contains(methodLower) {
            return .lifecycleNoise
        }

        if methodLower.contains("approval")
            || methodLower == "approval/reset"
            || methodLower == "turn/start/error"
            || methodLower == "turn/error"
            || methodLower == "runtime/terminated"
            || methodLower == "runtime/repair-suggested"
            || methodLower == "mods/reviewrequired"
        {
            return .critical
        }

        if itemTypeLower == "commandexecution"
            || titleLower.contains("commandexecution")
            || titleLower.contains("command execution")
            || methodLower.contains("command")
            || methodLower.contains("reasoning")
            || titleLower.contains("reasoning")
            || detailLower.contains("reasoning")
        {
            return .milestone
        }

        return .informational
    }

    static func isCriticalStderr(_ detail: String) -> Bool {
        if isKnownSkillLoaderStderrNoise(detail) {
            return false
        }

        let lowered = detail.lowercased()
        let hasExplicitErrorLevel = lowered.contains("error")
            || lowered.contains("failed")
            || lowered.contains("fatal")
            || lowered.contains("panic")

        if isRolloutPathStateDBWarning(detail) {
            return hasExplicitErrorLevel
        }

        let criticalPhrases = [
            "fatal",
            "panic",
            "error",
            "failed",
            "permission denied",
            "segmentation fault",
            "thread '",
            "abort trap",
            "illegal instruction",
            "bus error",
            "out of memory",
        ]
        return criticalPhrases.contains(where: lowered.contains)
    }

    static func isRolloutPathStateDBWarning(_ detail: String) -> Bool {
        let lowered = detail.lowercased()
        if lowered.contains("state db missing rollout path") {
            return true
        }

        return lowered.contains("state db missing")
            && lowered.contains("rollout path")
            && lowered.contains("thread")
    }

    static func normalizedStderrSignature(_ detail: String) -> String {
        var normalized = detail.lowercased()
        let patterns = [
            #"\d{4}-\d{2}-\d{2}t\d{2}:\d{2}:\d{2}(?:\.\d+)?z"#,
            #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#,
            #"\b\d+\b"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, range: range, withTemplate: "<x>")
        }

        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shouldSuppressFromTranscript(_ action: ActionCard) -> Bool {
        action.method.lowercased() == "runtime/stderr" && isKnownSkillLoaderStderrNoise(action.detail)
    }

    private static func isKnownSkillLoaderStderrNoise(_ detail: String) -> Bool {
        let lowered = detail.lowercased()
        return lowered.contains("codex_core::skills::loader")
            && lowered.contains("failed to stat skills entry")
    }
}

enum TranscriptPresentationBuilder {
    private struct TurnBucket: Hashable {
        let id: UUID
        var userMessage: ChatMessage?
        var assistantMessages: [ChatMessage] = []
        var actions: [ActionCard] = []
    }

    static func rows(
        entries: [TranscriptEntry],
        detailLevel: TranscriptDetailLevel,
        activeTurnContext: AppModel.ActiveTurnContext?
    ) -> [TranscriptPresentationRow] {
        if detailLevel == .detailed {
            return entries.compactMap {
                switch $0 {
                case let .message(message):
                    return TranscriptPresentationRow.message(message)
                case let .actionCard(action):
                    guard !TranscriptActionPolicy.shouldSuppressFromTranscript(action) else {
                        return nil
                    }
                    return TranscriptPresentationRow.action(action)
                }
            }
        }

        let buckets = turnBuckets(from: entries)
        let activeBucketID = activeBucketID(buckets: buckets, activeTurnContext: activeTurnContext)
        var rows: [TranscriptPresentationRow] = []

        for bucket in buckets {
            if let userMessage = bucket.userMessage {
                rows.append(.message(userMessage))
            }

            let isActiveBucket = bucket.id == activeBucketID
            if isActiveBucket {
                continue
            }

            let inlineActions = inlineActions(for: bucket.actions)
            for action in inlineActions {
                rows.append(.action(action))
            }

            let inlineActionIDs = Set(inlineActions.map(\.id))
            let hiddenActions = bucket.actions.filter { !inlineActionIDs.contains($0.id) }

            if let summary = turnSummary(
                for: bucket,
                hiddenActions: hiddenActions,
                detailLevel: detailLevel
            ) {
                rows.append(.turnSummary(summary))
            }

            for assistant in assistantMessagesForDisplay(in: bucket, detailLevel: detailLevel) {
                rows.append(.message(assistant))
            }
        }

        if let activeTurnContext {
            rows.append(.liveActivity(liveActivity(from: activeTurnContext)))
        }

        return rows
    }

    private static func turnBuckets(from entries: [TranscriptEntry]) -> [TurnBucket] {
        var buckets: [TurnBucket] = []
        var activeBucketIndex: Int?

        for entry in entries {
            switch entry {
            case let .message(message):
                if message.role == .user {
                    buckets.append(TurnBucket(id: message.id, userMessage: message))
                    activeBucketIndex = buckets.count - 1
                } else if let activeBucketIndex {
                    buckets[activeBucketIndex].assistantMessages.append(message)
                } else {
                    var synthetic = TurnBucket(id: message.id, userMessage: nil)
                    synthetic.assistantMessages.append(message)
                    buckets.append(synthetic)
                }

            case let .actionCard(action):
                if TranscriptActionPolicy.shouldSuppressFromTranscript(action) {
                    continue
                }
                if let activeBucketIndex {
                    buckets[activeBucketIndex].actions.append(action)
                } else {
                    var synthetic = TurnBucket(id: action.id, userMessage: nil)
                    synthetic.actions.append(action)
                    buckets.append(synthetic)
                }
            }
        }

        return buckets
    }

    private static func activeBucketID(
        buckets: [TurnBucket],
        activeTurnContext: AppModel.ActiveTurnContext?
    ) -> UUID? {
        guard let activeTurnContext else { return nil }

        if let exact = buckets.last(where: {
            $0.userMessage?.text.trimmingCharacters(in: .whitespacesAndNewlines) == activeTurnContext.userText
        }) {
            return exact.id
        }

        return buckets.last?.id
    }

    private static func assistantMessagesForDisplay(
        in bucket: TurnBucket,
        detailLevel: TranscriptDetailLevel
    ) -> [ChatMessage] {
        guard detailLevel != .detailed else {
            return bucket.assistantMessages
        }

        // Compact intermediary assistant updates into the turn summary
        // when runtime actions are present, and keep only the final answer visible.
        guard !bucket.actions.isEmpty,
              bucket.assistantMessages.count > 1,
              let finalMessage = bucket.assistantMessages.last
        else {
            return bucket.assistantMessages
        }

        return [finalMessage]
    }

    private static func inlineActions(for actions: [ActionCard]) -> [ActionCard] {
        var inline: [ActionCard] = []
        var criticalStderrBySignature: [String: [ActionCard]] = [:]
        var nonCriticalStderrBySignature: [String: [ActionCard]] = [:]

        for action in actions {
            let classification = TranscriptActionPolicy.classify(
                method: action.method,
                title: action.title,
                detail: action.detail
            )

            switch classification {
            case .critical:
                inline.append(action)
            case .stderr:
                let signature = TranscriptActionPolicy.normalizedStderrSignature(action.detail)
                if TranscriptActionPolicy.isCriticalStderr(action.detail) {
                    criticalStderrBySignature[signature, default: []].append(action)
                } else {
                    nonCriticalStderrBySignature[signature, default: []].append(action)
                }
            case .lifecycleNoise, .milestone, .informational:
                break
            }
        }

        for group in criticalStderrBySignature.values {
            guard !group.isEmpty else { continue }
            if group.count >= 3 {
                inline.append(coalescedStderrAction(group: group, isCritical: true))
            } else {
                inline.append(contentsOf: group)
            }
        }

        for group in nonCriticalStderrBySignature.values {
            guard group.count >= 3 else { continue }
            inline.append(coalescedStderrAction(group: group, isCritical: false))
        }

        return inline.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func coalescedStderrAction(group: [ActionCard], isCritical: Bool) -> ActionCard {
        let first = group[0]
        let sample = preview(first.detail, maxLength: 220)
        let titleSuffix = isCritical ? ", critical" : ""
        let collapseMessage = if isCritical {
            "Critical stderr repeated; matching lines were collapsed in chat view."
        } else {
            "Additional matching stderr lines were collapsed in chat view."
        }

        return ActionCard(
            threadID: first.threadID,
            method: "runtime/stderr/coalesced",
            title: "Runtime stderr repeated (\(group.count)x\(titleSuffix))",
            detail: "\(sample)\n\n\(collapseMessage)",
            createdAt: first.createdAt
        )
    }

    private static func turnSummary(
        for bucket: TurnBucket,
        hiddenActions: [ActionCard],
        detailLevel: TranscriptDetailLevel
    ) -> TurnSummaryPresentation? {
        guard bucket.userMessage != nil else {
            return nil
        }

        guard !bucket.actions.isEmpty else {
            return nil
        }

        if detailLevel == .chat, hiddenActions.isEmpty {
            return nil
        }

        let milestones = milestoneCounts(from: bucket.actions)
        let hasFailure = bucket.actions.contains {
            let method = $0.method.lowercased()
            let title = $0.title.lowercased()
            let detail = $0.detail.lowercased()
            return method.contains("error")
                || method.contains("failed")
                || title.contains("error")
                || title.contains("failed")
                || detail.contains("error")
                || detail.contains("failed")
        }

        return TurnSummaryPresentation(
            id: bucket.id,
            actions: bucket.actions,
            actionCount: bucket.actions.count,
            hiddenActionCount: hiddenActions.count,
            milestoneCounts: milestones,
            isFailure: hasFailure
        )
    }

    private static func liveActivity(from context: AppModel.ActiveTurnContext) -> LiveTurnActivityPresentation {
        LiveTurnActivityPresentation(
            id: context.localTurnID,
            turnID: context.localTurnID,
            userPreview: preview(context.userText, maxLength: 160),
            assistantPreview: preview(context.assistantText, maxLength: 220),
            latestActionTitle: context.actions.last?.title ?? "Streaming response",
            actions: context.actions,
            milestoneCounts: milestoneCounts(from: context.actions)
        )
    }

    private static func milestoneCounts(from actions: [ActionCard]) -> TranscriptMilestoneCounts {
        var counts = TranscriptMilestoneCounts()

        for action in actions {
            let method = action.method.lowercased()
            let title = action.title.lowercased()
            let detail = action.detail.lowercased()
            let classification = TranscriptActionPolicy.classify(
                method: action.method,
                title: action.title,
                detail: action.detail
            )

            if method.contains("reasoning")
                || title.contains("reasoning")
                || detail.contains("reasoning")
            {
                counts.reasoning += 1
            }

            if method.contains("command")
                || title.contains("commandexecution")
                || title.contains("command execution")
            {
                counts.commandExecution += 1
            }

            if classification == .stderr {
                if TranscriptActionPolicy.isCriticalStderr(action.detail) {
                    counts.errors += 1
                } else {
                    counts.warnings += 1
                }
            } else if method.contains("error")
                || title.contains("error")
                || title.contains("failed")
                || detail.contains("error")
                || detail.contains("failed")
            {
                counts.errors += 1
            } else if method.contains("warn")
                || title.contains("warn")
                || detail.contains("warn")
            {
                counts.warnings += 1
            }
        }

        return counts
    }

    private static func preview(_ text: String, maxLength: Int) -> String {
        let trimmed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else {
            return trimmed
        }
        let prefix = String(trimmed.prefix(maxLength))
        return "\(prefix)…"
    }
}
