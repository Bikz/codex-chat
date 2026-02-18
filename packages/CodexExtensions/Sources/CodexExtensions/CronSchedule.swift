import Foundation

public enum CronParseError: LocalizedError, Sendable {
    case invalidFieldCount
    case invalidField(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFieldCount:
            "Cron expression must contain 5 fields."
        case let .invalidField(field):
            "Invalid cron field: \(field)"
        }
    }
}

public struct CronSchedule: Hashable, Sendable {
    private let minutes: Set<Int>
    private let hours: Set<Int>
    private let daysOfMonth: Set<Int>
    private let months: Set<Int>
    private let weekdays: Set<Int>

    public init(expression: String) throws {
        let fields = expression
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard fields.count == 5 else {
            throw CronParseError.invalidFieldCount
        }

        minutes = try Self.parseField(fields[0], min: 0, max: 59)
        hours = try Self.parseField(fields[1], min: 0, max: 23)
        daysOfMonth = try Self.parseField(fields[2], min: 1, max: 31)
        months = try Self.parseField(fields[3], min: 1, max: 12)
        weekdays = try Self.parseWeekdayField(fields[4])
    }

    public func nextRun(after date: Date, timeZone: TimeZone = .current, calendar: Calendar = .current) -> Date? {
        var calendar = calendar
        calendar.timeZone = timeZone

        guard let normalized = calendar.date(bySetting: .second, value: 0, of: date),
              let start = calendar.date(byAdding: .minute, value: 1, to: normalized)
        else {
            return nil
        }

        // Cap search at ~400 days to avoid unbounded loops.
        let maxIterations = 400 * 24 * 60
        var cursor = start

        for _ in 0 ..< maxIterations {
            let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: cursor)
            guard let minute = components.minute,
                  let hour = components.hour,
                  let day = components.day,
                  let month = components.month,
                  let weekday = components.weekday
            else {
                return nil
            }

            // Calendar weekday: 1(Sun)...7(Sat). Normalize to cron 0(Sun)...6(Sat)
            let cronWeekday = (weekday + 6) % 7
            if minutes.contains(minute),
               hours.contains(hour),
               daysOfMonth.contains(day),
               months.contains(month),
               weekdays.contains(cronWeekday)
            {
                return cursor
            }

            guard let next = calendar.date(byAdding: .minute, value: 1, to: cursor) else {
                return nil
            }
            cursor = next
        }

        return nil
    }

    private static func parseWeekdayField(_ value: String) throws -> Set<Int> {
        let parsed = try parseField(value, min: 0, max: 7)
        if parsed.contains(7) {
            var adjusted = parsed
            adjusted.remove(7)
            adjusted.insert(0)
            return adjusted
        }
        return parsed
    }

    private static func parseField(_ value: String, min: Int, max: Int) throws -> Set<Int> {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CronParseError.invalidField(value)
        }

        if trimmed == "*" {
            return Set(min ... max)
        }

        var resolved = Set<Int>()
        for component in trimmed.split(separator: ",").map(String.init) {
            let piece = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else {
                throw CronParseError.invalidField(value)
            }

            if piece.contains("/") {
                let parts = piece.split(separator: "/", maxSplits: 1).map(String.init)
                guard parts.count == 2,
                      let step = Int(parts[1]),
                      step > 0
                else {
                    throw CronParseError.invalidField(value)
                }

                let rangePart = parts[0]
                let range: ClosedRange<Int>
                if rangePart == "*" {
                    range = min ... max
                } else if rangePart.contains("-") {
                    let bounds = rangePart.split(separator: "-", maxSplits: 1).map(String.init)
                    guard bounds.count == 2,
                          let lower = Int(bounds[0]),
                          let upper = Int(bounds[1]),
                          lower <= upper
                    else {
                        throw CronParseError.invalidField(value)
                    }
                    range = lower ... upper
                } else {
                    throw CronParseError.invalidField(value)
                }

                for candidate in range where candidate >= min && candidate <= max {
                    if (candidate - range.lowerBound) % step == 0 {
                        resolved.insert(candidate)
                    }
                }
                continue
            }

            if piece.contains("-") {
                let bounds = piece.split(separator: "-", maxSplits: 1).map(String.init)
                guard bounds.count == 2,
                      let lower = Int(bounds[0]),
                      let upper = Int(bounds[1]),
                      lower <= upper
                else {
                    throw CronParseError.invalidField(value)
                }

                guard lower >= min, upper <= max else {
                    throw CronParseError.invalidField(value)
                }

                for candidate in lower ... upper {
                    resolved.insert(candidate)
                }
                continue
            }

            guard let number = Int(piece), number >= min, number <= max else {
                throw CronParseError.invalidField(value)
            }
            resolved.insert(number)
        }

        guard !resolved.isEmpty else {
            throw CronParseError.invalidField(value)
        }
        return resolved
    }
}
