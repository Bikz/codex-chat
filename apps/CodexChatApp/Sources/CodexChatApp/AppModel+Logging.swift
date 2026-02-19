import CodexKit
import Foundation

extension AppModel {
    func sanitizeLogText(_ text: String) -> String {
        redactSensitiveText(in: stripANSIEscapeCodes(from: text))
    }

    func appendThreadLog(level: LogLevel, text: String, to threadID: UUID) {
        let sanitized = sanitizeLogText(text)
        var logs = threadLogsByThreadID[threadID, default: []]
        logs.append(ThreadLogEntry(level: level, text: sanitized))
        if logs.count > 1000 {
            logs.removeFirst(logs.count - 1000)
        }
        threadLogsByThreadID[threadID] = logs
    }

    func appendLog(_ level: LogLevel, _ message: String) {
        logs.append(LogEntry(level: level, message: sanitizeLogText(message)))
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    private func redactSensitiveText(in text: String) -> String {
        var sanitized = text
        let patterns = [
            "sk-[A-Za-z0-9_-]{16,}",
            "(?i)api[_-]?key\\s*[:=]\\s*[^\\s]+",
            "(?i)authorization\\s*:\\s*bearer\\s+[^\\s]+",
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(in: sanitized, range: range, withTemplate: "[REDACTED]")
        }

        return sanitized
    }

    private func stripANSIEscapeCodes(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
