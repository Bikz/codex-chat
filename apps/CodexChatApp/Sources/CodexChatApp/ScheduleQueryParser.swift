import Foundation

enum ScheduleQueryParser {
    enum Domain: Hashable {
        case calendar
        case reminders
    }

    enum Anchor: String, Hashable {
        case now
        case dayStart
    }

    struct Result: Hashable {
        let domain: Domain
        let rangeHours: Int
        let dayOffset: Int
        let anchor: Anchor

        func actionArguments(queryText: String) -> [String: String] {
            let trimmedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
            var arguments: [String: String] = [
                "rangeHours": String(rangeHours),
                "anchor": anchor.rawValue,
            ]

            if dayOffset != 0 {
                arguments["dayOffset"] = String(dayOffset)
            }
            if !trimmedQuery.isEmpty {
                arguments["queryText"] = trimmedQuery
            }
            return arguments
        }
    }

    static func parse(
        text: String,
        preferredDomain: Domain? = nil,
        now: Date = Date()
    ) -> Result? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let lowered = trimmed.lowercased()
        let explicitDomain = detectDomain(in: lowered)
        let hasPreferredDomain = preferredDomain != nil
        let temporal = temporalDescriptor(in: lowered, now: now)

        guard isLikelyScheduleQuery(
            lowered,
            temporal: temporal,
            hasExplicitDomain: explicitDomain != nil,
            hasPreferredDomain: hasPreferredDomain
        ) else {
            return nil
        }

        let domain = explicitDomain ?? preferredDomain
        guard let domain else {
            return nil
        }

        let rangeHours = normalizedRangeHours(from: lowered)
        let dayOffset = temporal ?? 0
        let anchor: Anchor = shouldUseNowAnchor(
            lowered: lowered,
            rangeHours: rangeHours,
            dayOffset: dayOffset
        ) ? .now : .dayStart

        return Result(
            domain: domain,
            rangeHours: rangeHours,
            dayOffset: dayOffset,
            anchor: anchor
        )
    }

    static func detectDomain(in lowered: String) -> Domain? {
        if lowered.range(of: #"\b(calendar|cal|agenda|schedule)\b"#, options: .regularExpression) != nil {
            return .calendar
        }

        if lowered.range(of: #"\b(reminder|reminders|todo|todos)\b"#, options: .regularExpression) != nil {
            return .reminders
        }

        return nil
    }

    private static func isLikelyScheduleQuery(
        _ lowered: String,
        temporal: Int?,
        hasExplicitDomain: Bool,
        hasPreferredDomain: Bool
    ) -> Bool {
        let hasRangeSignal = parseRangeHours(in: lowered) != nil || parseRangeDays(in: lowered) != nil
        let hasWindowSignal = lowered.contains("next week")
            || lowered.contains("this week")
            || lowered.contains("weekly")
        let hasQuestion = lowered.contains("?")
        let hasRequestPhrase = lowered.range(
            of: #"\b(show|check|list|see|tell me|what|whats|what's|do i have|what do i have|can you|could you|would you|have any|any events|any reminders)\b"#,
            options: .regularExpression
        ) != nil
        let hasTemporalSignal = temporal != nil

        if hasExplicitDomain, hasRequestPhrase {
            return true
        }

        if hasExplicitDomain, hasQuestion, hasTemporalSignal || hasRangeSignal || hasWindowSignal {
            return true
        }

        if hasPreferredDomain, !hasExplicitDomain, hasQuestion || hasRangeSignal || hasWindowSignal {
            return true
        }

        return false
    }

    private static func normalizedRangeHours(from lowered: String) -> Int {
        if let hours = parseRangeHours(in: lowered) {
            return min(max(hours, 1), 168)
        }

        if let days = parseRangeDays(in: lowered) {
            return min(max(days * 24, 1), 168)
        }

        if lowered.contains("next week")
            || lowered.contains("this week")
            || lowered.contains("weekly")
        {
            return 168
        }

        return 24
    }

    private static func parseRangeHours(in lowered: String) -> Int? {
        firstMatchedInt(
            pattern: #"(?:next|in|for)?\s*(\d{1,3})\s*(?:hours?|hrs?|hr|h)\b"#,
            in: lowered
        )
    }

    private static func parseRangeDays(in lowered: String) -> Int? {
        firstMatchedInt(
            pattern: #"(?:next|in|for)?\s*(\d{1,2})\s*(?:days?|day)\b"#,
            in: lowered
        )
    }

    private static func firstMatchedInt(pattern: String, in lowered: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let fullRange = NSRange(lowered.startIndex ..< lowered.endIndex, in: lowered)
        guard let match = regex.firstMatch(in: lowered, options: [], range: fullRange),
              let valueRange = Range(match.range(at: 1), in: lowered),
              let value = Int(lowered[valueRange])
        else {
            return nil
        }

        return value
    }

    private static func temporalDescriptor(in lowered: String, now: Date) -> Int? {
        if lowered.contains("day after tomorrow") {
            return 2
        }
        if lowered.contains("day before yesterday") {
            return -2
        }

        if lowered.contains("tomorrow")
            || lowered.contains("tmrw")
            || lowered.contains("tmr")
        {
            return 1
        }

        if lowered.contains("yesterday") {
            return -1
        }

        if lowered.contains("today") || lowered.contains("tonight") {
            return 0
        }

        if let weekdayOffset = parseWeekdayOffset(in: lowered, now: now) {
            return weekdayOffset
        }

        if let dateOffset = parseExplicitDateOffset(in: lowered, now: now) {
            return dateOffset
        }

        return nil
    }

    private static func parseWeekdayOffset(in lowered: String, now: Date) -> Int? {
        let pattern = #"\b(?:(next|this)\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let fullRange = NSRange(lowered.startIndex ..< lowered.endIndex, in: lowered)
        guard let match = regex.firstMatch(in: lowered, options: [], range: fullRange),
              let weekdayRange = Range(match.range(at: 2), in: lowered)
        else {
            return nil
        }

        let qualifier: String? = {
            guard let qualifierRange = Range(match.range(at: 1), in: lowered) else {
                return nil
            }
            return String(lowered[qualifierRange])
        }()

        let weekdayToken = String(lowered[weekdayRange])
        guard let targetWeekday = weekdayComponent(for: weekdayToken) else {
            return nil
        }

        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: now)
        var delta = (targetWeekday - currentWeekday + 7) % 7

        if qualifier == "next", delta == 0 {
            delta = 7
        }

        return delta
    }

    private static func weekdayComponent(for token: String) -> Int? {
        switch token {
        case "sunday":
            1
        case "monday":
            2
        case "tuesday":
            3
        case "wednesday":
            4
        case "thursday":
            5
        case "friday":
            6
        case "saturday":
            7
        default:
            nil
        }
    }

    private static func parseExplicitDateOffset(in lowered: String, now: Date) -> Int? {
        if let isoOffset = parseISODateOffset(in: lowered, now: now) {
            return isoOffset
        }
        if let slashOffset = parseSlashDateOffset(in: lowered, now: now) {
            return slashOffset
        }
        return nil
    }

    private static func parseISODateOffset(in lowered: String, now: Date) -> Int? {
        let pattern = #"\b(\d{4})-(\d{2})-(\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let parts = firstDateParts(from: lowered, with: regex),
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        return dayOffsetFromNow(year: year, month: month, day: day, now: now)
    }

    private static func parseSlashDateOffset(in lowered: String, now: Date) -> Int? {
        let pattern = #"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let parts = firstDateParts(from: lowered, with: regex)
        else {
            return nil
        }

        guard let month = Int(parts[0]),
              let day = Int(parts[1])
        else {
            return nil
        }

        let calendar = Calendar.current
        let nowYear = calendar.component(.year, from: now)
        let rawYear = parts.count > 2 ? parts[2] : ""
        let year: Int = {
            guard !rawYear.isEmpty, let parsed = Int(rawYear) else {
                return nowYear
            }
            if rawYear.count == 2 {
                return 2000 + parsed
            }
            return parsed
        }()

        return dayOffsetFromNow(year: year, month: month, day: day, now: now)
    }

    private static func firstDateParts(
        from lowered: String,
        with regex: NSRegularExpression
    ) -> [String]? {
        let fullRange = NSRange(lowered.startIndex ..< lowered.endIndex, in: lowered)
        guard let match = regex.firstMatch(in: lowered, options: [], range: fullRange) else {
            return nil
        }

        var parts: [String] = []
        for index in 1 ..< match.numberOfRanges {
            if let range = Range(match.range(at: index), in: lowered) {
                parts.append(String(lowered[range]))
            }
        }
        return parts
    }

    private static func dayOffsetFromNow(
        year: Int,
        month: Int,
        day: Int,
        now: Date
    ) -> Int? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day

        let calendar = Calendar.current
        guard let targetDate = calendar.date(from: components) else {
            return nil
        }

        let startNow = calendar.startOfDay(for: now)
        let startTarget = calendar.startOfDay(for: targetDate)
        return calendar.dateComponents([.day], from: startNow, to: startTarget).day
    }

    private static func shouldUseNowAnchor(
        lowered: String,
        rangeHours: Int,
        dayOffset: Int
    ) -> Bool {
        guard dayOffset == 0, rangeHours < 24 else {
            return false
        }

        return lowered.contains("next")
            || lowered.contains("in ")
            || lowered.contains("hours")
            || lowered.contains("hrs")
            || lowered.contains(" hr ")
    }
}
