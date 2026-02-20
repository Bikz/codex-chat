import CodexChatCore
import Foundation
#if canImport(EventKit)
    import EventKit
#endif

public struct CalendarEvent: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let calendarName: String
    public let startAt: Date
    public let endAt: Date
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?

    public init(
        id: String,
        title: String,
        calendarName: String,
        startAt: Date,
        endAt: Date,
        isAllDay: Bool,
        location: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.calendarName = calendarName
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
    }
}

public protocol CalendarEventSource: Sendable {
    func events(from start: Date, to end: Date) async throws -> [CalendarEvent]
}

public final class CalendarTodayAction: ComputerActionProvider {
    private let eventSource: any CalendarEventSource
    private let nowProvider: @Sendable () -> Date

    public init(
        eventSource: (any CalendarEventSource)? = nil,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.eventSource = eventSource ?? EventKitCalendarEventSource()
        self.nowProvider = nowProvider
    }

    public let actionID = "calendar.today"
    public let displayName = "Calendar Today"
    public let safetyLevel: ComputerActionSafetyLevel = .readOnly
    public let requiresConfirmation = false

    public func preview(request: ComputerActionRequest) async throws -> ComputerActionPreviewArtifact {
        let now = nowProvider()
        let (start, end, clampedHours, dayOffset, anchor) = Self.queryWindow(
            now: now,
            arguments: request.arguments
        )
        let events = try await eventSource.events(from: start, to: end)
        let sorted = events.sorted { lhs, rhs in
            if lhs.startAt != rhs.startAt { return lhs.startAt < rhs.startAt }
            return lhs.title < rhs.title
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let markdown: String = if sorted.isEmpty {
            "No events found for the selected range."
        } else {
            sorted.map { event in
                if event.isAllDay {
                    return "- **\(event.title)** (all day) — \(event.calendarName)"
                }
                let start = formatter.string(from: event.startAt)
                let end = formatter.string(from: event.endAt)
                return "- **\(event.title)** (\(start) – \(end)) — \(event.calendarName)"
            }.joined(separator: "\n")
        }

        let summary = sorted.isEmpty
            ? "No calendar events in range."
            : "Found \(sorted.count) event(s)."

        let data = Self.encodeEvents(sorted)
        return ComputerActionPreviewArtifact(
            actionID: actionID,
            runContextID: request.runContextID,
            title: "Calendar Overview",
            summary: summary,
            detailsMarkdown: markdown,
            data: [
                "events": data,
                "rangeHours": String(clampedHours),
                "dayOffset": String(dayOffset),
                "anchor": anchor,
            ]
        )
    }

    public func execute(
        request: ComputerActionRequest,
        preview: ComputerActionPreviewArtifact
    ) async throws -> ComputerActionExecutionResult {
        try validate(preview: preview, request: request)
        let events = Self.decodeEvents(preview.data["events"])
        let summary = events.isEmpty
            ? "Calendar check completed with no events."
            : "Calendar check completed with \(events.count) event(s)."

        return ComputerActionExecutionResult(
            actionID: actionID,
            runContextID: request.runContextID,
            summary: summary,
            detailsMarkdown: preview.detailsMarkdown
        )
    }

    private static func encodeEvents(_ events: [CalendarEvent]) -> String {
        if let data = try? JSONEncoder().encode(events),
           let text = String(data: data, encoding: .utf8)
        {
            return text
        }
        return "[]"
    }

    private static func decodeEvents(_ text: String?) -> [CalendarEvent] {
        guard let text,
              let data = text.data(using: .utf8),
              let events = try? JSONDecoder().decode([CalendarEvent].self, from: data)
        else {
            return []
        }
        return events
    }

    private static func queryWindow(
        now: Date,
        arguments: [String: String]
    ) -> (start: Date, end: Date, clampedHours: Int, dayOffset: Int, anchor: String) {
        let calendar = Calendar.current
        let hours = Int(arguments["rangeHours"] ?? "24") ?? 24
        let clampedHours = max(1, min(168, hours))
        let parsedOffset = Int(arguments["dayOffset"] ?? "0") ?? 0
        let dayOffset = max(-30, min(30, parsedOffset))
        let anchor = arguments["anchor"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "dayStart"

        let offsetReference = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        let start: Date = if anchor == "now" {
            offsetReference
        } else {
            calendar.startOfDay(for: offsetReference)
        }

        let end = calendar.date(byAdding: .hour, value: clampedHours, to: start)
            ?? start.addingTimeInterval(TimeInterval(clampedHours * 3600))

        return (start, end, clampedHours, dayOffset, anchor)
    }
}

public final class EventKitCalendarEventSource: CalendarEventSource {
    public init() {}

    public func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        #if canImport(EventKit)
            let store = EKEventStore()
            let granted = try await requestAccess(store: store)
            guard granted else {
                throw ComputerActionError.permissionDenied(
                    "Calendar access is denied. Enable Calendar permissions in System Settings > Privacy & Security > Calendars."
                )
            }

            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            return store.events(matching: predicate).map { event in
                CalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title,
                    calendarName: event.calendar.title,
                    startAt: event.startDate,
                    endAt: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location,
                    notes: event.notes
                )
            }
        #else
            throw ComputerActionError.unsupported("Calendar event access is unavailable on this platform.")
        #endif
    }

    #if canImport(EventKit)
        @available(macOS 14.0, *)
        private func requestAccessV14(store: EKEventStore) async throws -> Bool {
            try await store.requestFullAccessToEvents()
        }

        private func requestAccess(store: EKEventStore) async throws -> Bool {
            if #available(macOS 14.0, *) {
                return try await requestAccessV14(store: store)
            }

            return try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(to: .event) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    #endif
}
