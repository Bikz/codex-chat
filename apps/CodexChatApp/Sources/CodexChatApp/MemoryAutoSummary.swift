import CodexChatCore
import Foundation

enum MemoryAutoSummary {
    static func markdown(
        timestamp: Date,
        threadID: UUID,
        userText: String,
        assistantText: String,
        actions: [ActionCard],
        mode: ProjectMemoryWriteMode
    ) -> String {
        let time = timestampString(timestamp)
        let collapsedUser = collapsed(userText, limit: 240)
        let collapsedAssistant = collapsed(assistantText, limit: 320)

        var lines: [String] = []
        lines.append("## \(time)")
        lines.append("")
        lines.append("- Thread: `\(threadID.uuidString)`")
        lines.append("- User: \(collapsedUser.isEmpty ? "_Empty_" : collapsedUser)")
        lines.append("- Assistant: \(collapsedAssistant.isEmpty ? "_Empty_" : collapsedAssistant)")

        if !actions.isEmpty {
            lines.append("")
            lines.append("Actions:")
            for action in actions.prefix(8) {
                lines.append("- \(action.title) (`\(action.method)`)")
            }
        }

        if mode == .summariesAndKeyFacts {
            let facts = extractKeyFacts(userText: userText, assistantText: assistantText)
            if !facts.isEmpty {
                lines.append("")
                lines.append("Key facts (auto-extracted; verify):")
                for fact in facts.prefix(6) {
                    lines.append("- \(collapsed(fact, limit: 180))")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func collapsed(_ text: String, limit: Int) -> String {
        let compact = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard compact.count > limit else {
            return compact
        }
        return String(compact.prefix(max(0, limit - 1))) + "…"
    }

    private static func extractKeyFacts(userText: String, assistantText: String) -> [String] {
        let lines = assistantText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var facts: [String] = []
        facts.reserveCapacity(6)

        for line in lines {
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let cleaned = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    facts.append(cleaned)
                }
            } else if line.hasPrefix("• ") {
                let cleaned = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    facts.append(cleaned)
                }
            }
            if facts.count >= 6 {
                break
            }
        }

        if !facts.isEmpty {
            return facts
        }

        let assistantCompact = assistantText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if assistantCompact.isEmpty {
            return []
        }

        // Fallback: first couple sentence-like fragments.
        var fragments: [String] = []
        var current = ""
        for ch in assistantCompact {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    fragments.append(trimmed)
                }
                current = ""
                if fragments.count >= 3 {
                    break
                }
            }
        }
        if fragments.isEmpty {
            fragments.append(collapsed(assistantCompact, limit: 180))
        }
        return fragments
    }
}
