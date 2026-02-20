import CodexChatCore
import Foundation
#if canImport(EventKit)
    import EventKit
#endif

public struct CalendarEventDraft: Hashable, Sendable, Codable {
    public let title: String
    public let calendarName: String?
    public let startAt: Date
    public let endAt: Date
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?

    public init(
        title: String,
        calendarName: String?,
        startAt: Date,
        endAt: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?
    ) {
        self.title = title
        self.calendarName = calendarName
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
    }
}

public protocol CalendarEventMutationStore: Sendable {
    func events(from start: Date, to end: Date) async throws -> [CalendarEvent]
    func event(withID id: String) async throws -> CalendarEvent?
    func createEvent(_ draft: CalendarEventDraft) async throws -> CalendarEvent
    func updateEvent(id: String, draft: CalendarEventDraft) async throws -> CalendarEvent
    func deleteEvent(id: String) async throws -> CalendarEvent
}

public final class CalendarCreateAction: ComputerActionProvider {
    private struct CreatePayload: Hashable, Codable {
        let title: String
        let calendarName: String?
        let startAt: Date
        let endAt: Date
        let isAllDay: Bool
        let location: String?
        let notes: String?

        var draft: CalendarEventDraft {
            CalendarEventDraft(
                title: title,
                calendarName: calendarName,
                startAt: startAt,
                endAt: endAt,
                isAllDay: isAllDay,
                location: location,
                notes: notes
            )
        }
    }

    private let store: any CalendarEventMutationStore

    public init(store: (any CalendarEventMutationStore)? = nil) {
        self.store = store ?? EventKitCalendarEventMutationStore()
    }

    public let actionID = "calendar.create"
    public let displayName = "Calendar Create"
    public let safetyLevel: ComputerActionSafetyLevel = .externallyVisible
    public let requiresConfirmation = true

    public func preview(request: ComputerActionRequest) async throws -> ComputerActionPreviewArtifact {
        let payload = try parsePayload(from: request.arguments)
        let conflicts = try await overlappingEvents(for: payload.draft, excludingEventID: nil)

        let details = """
        Proposed event:
        - Title: `\(payload.title)`
        - Calendar: `\(payload.calendarName ?? "Default")`
        - Start: `\(CalendarCRUDFormatting.isoString(from: payload.startAt))`
        - End: `\(CalendarCRUDFormatting.isoString(from: payload.endAt))`
        - All-day: `\(payload.isAllDay ? "yes" : "no")`

        \(conflictsMarkdown(conflicts))
        """

        let summary = conflicts.isEmpty
            ? "Ready to create calendar event `\(payload.title)`."
            : "Ready to create event `\(payload.title)` with \(conflicts.count) overlap warning(s)."

        return ComputerActionPreviewArtifact(
            actionID: actionID,
            runContextID: request.runContextID,
            title: "Create Calendar Event",
            summary: summary,
            detailsMarkdown: details,
            data: [
                "payload": CalendarCRUDFormatting.encode(payload),
                "conflicts": CalendarCRUDFormatting.encode(conflicts),
            ]
        )
    }

    public func execute(
        request: ComputerActionRequest,
        preview: ComputerActionPreviewArtifact
    ) async throws -> ComputerActionExecutionResult {
        try validate(preview: preview, request: request)
        guard let encodedPayload = preview.data["payload"],
              let previewPayload = CalendarCRUDFormatting.decode(CreatePayload.self, from: encodedPayload)
        else {
            throw ComputerActionError.invalidPreviewArtifact
        }

        let currentPayload = try parsePayload(from: request.arguments)
        guard currentPayload == previewPayload else {
            throw ComputerActionError.invalidArguments(
                "Calendar create request changed after preview. Generate a fresh preview before creating."
            )
        }

        let created = try await store.createEvent(previewPayload.draft)
        return ComputerActionExecutionResult(
            actionID: actionID,
            runContextID: request.runContextID,
            summary: "Created calendar event `\(created.title)`.",
            detailsMarkdown: """
            Event created successfully.

            - ID: `\(created.id)`
            - Calendar: `\(created.calendarName)`
            - Start: `\(CalendarCRUDFormatting.isoString(from: created.startAt))`
            - End: `\(CalendarCRUDFormatting.isoString(from: created.endAt))`
            """,
            metadata: [
                "eventID": created.id,
                "title": created.title,
            ]
        )
    }

    private func parsePayload(from arguments: [String: String]) throws -> CreatePayload {
        let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            throw ComputerActionError.invalidArguments("Provide `title` for calendar.create.")
        }

        let startAt = try CalendarCRUDFormatting.parseDate(
            from: arguments,
            keys: ["startAt", "startISO", "start"]
        )
        let endAt = try CalendarCRUDFormatting.parseDate(
            from: arguments,
            keys: ["endAt", "endISO", "end"]
        )

        guard endAt > startAt else {
            throw ComputerActionError.invalidArguments("`endAt` must be later than `startAt`.")
        }

        return CreatePayload(
            title: title,
            calendarName: CalendarCRUDFormatting.optionalText(arguments["calendarName"]),
            startAt: startAt,
            endAt: endAt,
            isAllDay: CalendarCRUDFormatting.parseBool(arguments["isAllDay"]),
            location: CalendarCRUDFormatting.optionalText(arguments["location"]),
            notes: CalendarCRUDFormatting.optionalText(arguments["notes"])
        )
    }

    private func overlappingEvents(
        for draft: CalendarEventDraft,
        excludingEventID: String?
    ) async throws -> [CalendarEvent] {
        let events = try await store.events(from: draft.startAt, to: draft.endAt)
        return events.filter { event in
            if let excludingEventID, event.id == excludingEventID {
                return false
            }
            return draft.startAt < event.endAt && event.startAt < draft.endAt
        }
        .sorted { lhs, rhs in
            if lhs.startAt != rhs.startAt {
                return lhs.startAt < rhs.startAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func conflictsMarkdown(_ conflicts: [CalendarEvent]) -> String {
        guard !conflicts.isEmpty else {
            return "Overlap warnings: _none_"
        }
        let rows = conflicts.map { event in
            "- `\(event.title)` (\(CalendarCRUDFormatting.shortTimeString(from: event.startAt)) - \(CalendarCRUDFormatting.shortTimeString(from: event.endAt)))"
        }
        return """
        Overlap warnings:
        \(rows.joined(separator: "\n"))
        """
    }
}

public final class CalendarUpdateAction: ComputerActionProvider {
    private struct UpdateRequestPayload: Hashable, Codable {
        let eventID: String
        let title: String?
        let calendarName: String?
        let startAt: Date?
        let endAt: Date?
        let isAllDay: Bool?
        let location: String?
        let notes: String?
    }

    private struct UpdatePreviewPayload: Hashable, Codable {
        let request: UpdateRequestPayload
        let resolvedDraft: CalendarEventDraft
    }

    private let store: any CalendarEventMutationStore

    public init(store: (any CalendarEventMutationStore)? = nil) {
        self.store = store ?? EventKitCalendarEventMutationStore()
    }

    public let actionID = "calendar.update"
    public let displayName = "Calendar Update"
    public let safetyLevel: ComputerActionSafetyLevel = .externallyVisible
    public let requiresConfirmation = true

    public func preview(request: ComputerActionRequest) async throws -> ComputerActionPreviewArtifact {
        let requestPayload = try parseRequestPayload(from: request.arguments)
        guard let existing = try await store.event(withID: requestPayload.eventID) else {
            throw ComputerActionError.invalidArguments("Calendar event not found for ID \(requestPayload.eventID).")
        }

        let resolvedDraft = try resolveDraft(requestPayload: requestPayload, existing: existing)
        let conflicts = try await overlappingEvents(
            for: resolvedDraft,
            excludingEventID: requestPayload.eventID
        )

        let details = """
        Existing event:
        - Title: `\(existing.title)`
        - Calendar: `\(existing.calendarName)`
        - Start: `\(CalendarCRUDFormatting.isoString(from: existing.startAt))`
        - End: `\(CalendarCRUDFormatting.isoString(from: existing.endAt))`

        Updated event:
        - Title: `\(resolvedDraft.title)`
        - Calendar: `\(resolvedDraft.calendarName ?? existing.calendarName)`
        - Start: `\(CalendarCRUDFormatting.isoString(from: resolvedDraft.startAt))`
        - End: `\(CalendarCRUDFormatting.isoString(from: resolvedDraft.endAt))`
        - All-day: `\(resolvedDraft.isAllDay ? "yes" : "no")`

        \(conflictsMarkdown(conflicts))
        """

        let summary = conflicts.isEmpty
            ? "Ready to update calendar event `\(existing.title)`."
            : "Ready to update `\(existing.title)` with \(conflicts.count) overlap warning(s)."

        return ComputerActionPreviewArtifact(
            actionID: actionID,
            runContextID: request.runContextID,
            title: "Update Calendar Event",
            summary: summary,
            detailsMarkdown: details,
            data: [
                "payload": CalendarCRUDFormatting.encode(
                    UpdatePreviewPayload(request: requestPayload, resolvedDraft: resolvedDraft)
                ),
                "existingEvent": CalendarCRUDFormatting.encode(existing),
            ]
        )
    }

    public func execute(
        request: ComputerActionRequest,
        preview: ComputerActionPreviewArtifact
    ) async throws -> ComputerActionExecutionResult {
        try validate(preview: preview, request: request)
        guard let encodedPayload = preview.data["payload"],
              let previewPayload = CalendarCRUDFormatting.decode(UpdatePreviewPayload.self, from: encodedPayload)
        else {
            throw ComputerActionError.invalidPreviewArtifact
        }

        let currentRequestPayload = try parseRequestPayload(from: request.arguments)
        guard currentRequestPayload == previewPayload.request else {
            throw ComputerActionError.invalidArguments(
                "Calendar update request changed after preview. Generate a fresh preview before updating."
            )
        }

        let updated = try await store.updateEvent(
            id: previewPayload.request.eventID,
            draft: previewPayload.resolvedDraft
        )

        return ComputerActionExecutionResult(
            actionID: actionID,
            runContextID: request.runContextID,
            summary: "Updated calendar event `\(updated.title)`.",
            detailsMarkdown: """
            Event updated successfully.

            - ID: `\(updated.id)`
            - Calendar: `\(updated.calendarName)`
            - Start: `\(CalendarCRUDFormatting.isoString(from: updated.startAt))`
            - End: `\(CalendarCRUDFormatting.isoString(from: updated.endAt))`
            """,
            metadata: [
                "eventID": updated.id,
                "title": updated.title,
            ]
        )
    }

    private func parseRequestPayload(from arguments: [String: String]) throws -> UpdateRequestPayload {
        let eventID = (arguments["eventID"] ?? arguments["id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventID.isEmpty else {
            throw ComputerActionError.invalidArguments("Provide `eventID` for calendar.update.")
        }

        let startAt = try CalendarCRUDFormatting.parseOptionalDate(
            from: arguments,
            keys: ["startAt", "startISO", "start"]
        )
        let endAt = try CalendarCRUDFormatting.parseOptionalDate(
            from: arguments,
            keys: ["endAt", "endISO", "end"]
        )

        let requestPayload = UpdateRequestPayload(
            eventID: eventID,
            title: CalendarCRUDFormatting.optionalText(arguments["title"]),
            calendarName: CalendarCRUDFormatting.optionalText(arguments["calendarName"]),
            startAt: startAt,
            endAt: endAt,
            isAllDay: CalendarCRUDFormatting.parseOptionalBool(arguments["isAllDay"]),
            location: CalendarCRUDFormatting.optionalText(arguments["location"]),
            notes: CalendarCRUDFormatting.optionalText(arguments["notes"])
        )

        if requestPayload.title == nil,
           requestPayload.calendarName == nil,
           requestPayload.startAt == nil,
           requestPayload.endAt == nil,
           requestPayload.isAllDay == nil,
           requestPayload.location == nil,
           requestPayload.notes == nil
        {
            throw ComputerActionError.invalidArguments("Provide at least one field to update for calendar.update.")
        }

        return requestPayload
    }

    private func resolveDraft(
        requestPayload: UpdateRequestPayload,
        existing: CalendarEvent
    ) throws -> CalendarEventDraft {
        let startAt = requestPayload.startAt ?? existing.startAt
        let endAt = requestPayload.endAt ?? existing.endAt
        guard endAt > startAt else {
            throw ComputerActionError.invalidArguments("Updated end time must be later than start time.")
        }

        return CalendarEventDraft(
            title: requestPayload.title ?? existing.title,
            calendarName: requestPayload.calendarName ?? existing.calendarName,
            startAt: startAt,
            endAt: endAt,
            isAllDay: requestPayload.isAllDay ?? existing.isAllDay,
            location: requestPayload.location ?? existing.location,
            notes: requestPayload.notes ?? existing.notes
        )
    }

    private func overlappingEvents(
        for draft: CalendarEventDraft,
        excludingEventID: String?
    ) async throws -> [CalendarEvent] {
        let events = try await store.events(from: draft.startAt, to: draft.endAt)
        return events.filter { event in
            if let excludingEventID, event.id == excludingEventID {
                return false
            }
            return draft.startAt < event.endAt && event.startAt < draft.endAt
        }
        .sorted { lhs, rhs in
            if lhs.startAt != rhs.startAt {
                return lhs.startAt < rhs.startAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func conflictsMarkdown(_ conflicts: [CalendarEvent]) -> String {
        guard !conflicts.isEmpty else {
            return "Overlap warnings: _none_"
        }
        let rows = conflicts.map { event in
            "- `\(event.title)` (\(CalendarCRUDFormatting.shortTimeString(from: event.startAt)) - \(CalendarCRUDFormatting.shortTimeString(from: event.endAt)))"
        }
        return """
        Overlap warnings:
        \(rows.joined(separator: "\n"))
        """
    }
}

public final class CalendarDeleteAction: ComputerActionProvider {
    private struct DeletePayload: Hashable, Codable {
        let eventID: String
    }

    private let store: any CalendarEventMutationStore

    public init(store: (any CalendarEventMutationStore)? = nil) {
        self.store = store ?? EventKitCalendarEventMutationStore()
    }

    public let actionID = "calendar.delete"
    public let displayName = "Calendar Delete"
    public let safetyLevel: ComputerActionSafetyLevel = .destructive
    public let requiresConfirmation = true

    public func preview(request: ComputerActionRequest) async throws -> ComputerActionPreviewArtifact {
        let payload = try parsePayload(arguments: request.arguments)
        guard let existing = try await store.event(withID: payload.eventID) else {
            throw ComputerActionError.invalidArguments("Calendar event not found for ID \(payload.eventID).")
        }

        let details = """
        Event scheduled for deletion:
        - ID: `\(existing.id)`
        - Title: `\(existing.title)`
        - Calendar: `\(existing.calendarName)`
        - Start: `\(CalendarCRUDFormatting.isoString(from: existing.startAt))`
        - End: `\(CalendarCRUDFormatting.isoString(from: existing.endAt))`
        """

        return ComputerActionPreviewArtifact(
            actionID: actionID,
            runContextID: request.runContextID,
            title: "Delete Calendar Event",
            summary: "Ready to delete calendar event `\(existing.title)`.",
            detailsMarkdown: details,
            data: [
                "payload": CalendarCRUDFormatting.encode(payload),
                "eventTitle": existing.title,
            ]
        )
    }

    public func execute(
        request: ComputerActionRequest,
        preview: ComputerActionPreviewArtifact
    ) async throws -> ComputerActionExecutionResult {
        try validate(preview: preview, request: request)
        guard let encodedPayload = preview.data["payload"],
              let previewPayload = CalendarCRUDFormatting.decode(DeletePayload.self, from: encodedPayload)
        else {
            throw ComputerActionError.invalidPreviewArtifact
        }

        let currentPayload = try parsePayload(arguments: request.arguments)
        guard previewPayload == currentPayload else {
            throw ComputerActionError.invalidArguments(
                "Calendar delete request changed after preview. Generate a fresh preview before deleting."
            )
        }

        let deleted = try await store.deleteEvent(id: previewPayload.eventID)
        return ComputerActionExecutionResult(
            actionID: actionID,
            runContextID: request.runContextID,
            summary: "Deleted calendar event `\(deleted.title)`.",
            detailsMarkdown: """
            Event deleted successfully.

            - ID: `\(deleted.id)`
            - Title: `\(deleted.title)`
            - Calendar: `\(deleted.calendarName)`
            """,
            metadata: [
                "eventID": deleted.id,
                "title": deleted.title,
            ]
        )
    }

    private func parsePayload(arguments: [String: String]) throws -> DeletePayload {
        let eventID = (arguments["eventID"] ?? arguments["id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventID.isEmpty else {
            throw ComputerActionError.invalidArguments("Provide `eventID` for calendar.delete.")
        }
        return DeletePayload(eventID: eventID)
    }
}

public final class EventKitCalendarEventMutationStore: CalendarEventMutationStore {
    public init() {}

    public func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        #if canImport(EventKit)
            let store = EKEventStore()
            try await requestAccess(store: store)
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            return store.events(matching: predicate).map(Self.makeCalendarEvent)
        #else
            throw ComputerActionError.unsupported("Calendar event access is unavailable on this platform.")
        #endif
    }

    public func event(withID id: String) async throws -> CalendarEvent? {
        #if canImport(EventKit)
            let store = EKEventStore()
            try await requestAccess(store: store)
            guard let event = store.event(withIdentifier: id) else {
                return nil
            }
            return Self.makeCalendarEvent(event)
        #else
            throw ComputerActionError.unsupported("Calendar event access is unavailable on this platform.")
        #endif
    }

    public func createEvent(_ draft: CalendarEventDraft) async throws -> CalendarEvent {
        #if canImport(EventKit)
            let store = EKEventStore()
            try await requestAccess(store: store)

            let event = EKEvent(eventStore: store)
            try populate(event: event, draft: draft, store: store)
            do {
                try store.save(event, span: .thisEvent, commit: true)
            } catch {
                throw normalizeMutationError(error)
            }
            return Self.makeCalendarEvent(event)
        #else
            throw ComputerActionError.unsupported("Calendar event access is unavailable on this platform.")
        #endif
    }

    public func updateEvent(id: String, draft: CalendarEventDraft) async throws -> CalendarEvent {
        #if canImport(EventKit)
            let store = EKEventStore()
            try await requestAccess(store: store)
            guard let event = store.event(withIdentifier: id) else {
                throw ComputerActionError.invalidArguments("Calendar event not found for ID \(id).")
            }

            try populate(event: event, draft: draft, store: store)
            do {
                try store.save(event, span: .thisEvent, commit: true)
            } catch {
                throw normalizeMutationError(error)
            }
            return Self.makeCalendarEvent(event)
        #else
            throw ComputerActionError.unsupported("Calendar event access is unavailable on this platform.")
        #endif
    }

    public func deleteEvent(id: String) async throws -> CalendarEvent {
        #if canImport(EventKit)
            let store = EKEventStore()
            try await requestAccess(store: store)
            guard let event = store.event(withIdentifier: id) else {
                throw ComputerActionError.invalidArguments("Calendar event not found for ID \(id).")
            }
            let deleted = Self.makeCalendarEvent(event)
            do {
                try store.remove(event, span: .thisEvent, commit: true)
            } catch {
                throw normalizeMutationError(error)
            }
            return deleted
        #else
            throw ComputerActionError.unsupported("Calendar event access is unavailable on this platform.")
        #endif
    }

    #if canImport(EventKit)
        @available(macOS 14.0, *)
        private func requestAccessV14(store: EKEventStore) async throws -> Bool {
            try await store.requestFullAccessToEvents()
        }

        private func requestAccess(store: EKEventStore) async throws {
            do {
                let granted: Bool = if #available(macOS 14.0, *) {
                    try await requestAccessV14(store: store)
                } else {
                    try await withCheckedThrowingContinuation { continuation in
                        store.requestAccess(to: .event) { allowed, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: allowed)
                            }
                        }
                    }
                }

                guard granted else {
                    throw permissionDeniedError()
                }
            } catch {
                if Self.isPermissionError(error) {
                    throw permissionDeniedError()
                }
                throw ComputerActionError.executionFailed(
                    "Failed to request calendar access: \(error.localizedDescription)"
                )
            }
        }

        private func populate(event: EKEvent, draft: CalendarEventDraft, store: EKEventStore) throws {
            event.title = draft.title
            event.startDate = draft.startAt
            event.endDate = draft.endAt
            event.isAllDay = draft.isAllDay
            event.location = CalendarCRUDFormatting.optionalText(draft.location)
            event.notes = CalendarCRUDFormatting.optionalText(draft.notes)

            let selectedCalendar: EKCalendar?
            if let requestedName = CalendarCRUDFormatting.optionalText(draft.calendarName) {
                selectedCalendar = store.calendars(for: .event).first(where: {
                    $0.title.localizedCaseInsensitiveCompare(requestedName) == .orderedSame
                })
                guard selectedCalendar != nil else {
                    throw ComputerActionError.invalidArguments("Calendar named `\(requestedName)` was not found.")
                }
            } else {
                selectedCalendar = store.defaultCalendarForNewEvents
            }

            guard let selectedCalendar else {
                throw ComputerActionError.executionFailed("No writable calendar is available.")
            }
            event.calendar = selectedCalendar
        }

        private static func makeCalendarEvent(_ event: EKEvent) -> CalendarEvent {
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

        private func normalizeMutationError(_ error: Error) -> ComputerActionError {
            if Self.isPermissionError(error) {
                return permissionDeniedError()
            }
            return ComputerActionError.executionFailed(error.localizedDescription)
        }

        private static func isPermissionError(_ error: Error) -> Bool {
            let nsError = error as NSError
            let message = nsError.localizedDescription.lowercased()

            if nsError.domain == EKErrorDomain {
                return message.contains("not authorized")
                    || message.contains("permission")
                    || message.contains("denied")
            }

            return message.contains("not authorized") || message.contains("permission")
        }

        private func permissionDeniedError() -> ComputerActionError {
            .permissionDenied(
                "Calendar access is denied. Enable Calendar permissions in System Settings > Privacy & Security > Calendars."
            )
        }
    #endif
}

private enum CalendarCRUDFormatting {
    private static func makeISOFormatter(includeFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        if includeFractionalSeconds {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        } else {
            formatter.formatOptions = [.withInternetDateTime]
        }
        return formatter
    }

    private static func makeShortFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    static func isoString(from date: Date) -> String {
        makeISOFormatter(includeFractionalSeconds: true).string(from: date)
    }

    static func shortTimeString(from date: Date) -> String {
        makeShortFormatter().string(from: date)
    }

    static func encode(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        guard let data = text.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func parseDate(from arguments: [String: String], keys: [String]) throws -> Date {
        if let date = try parseOptionalDate(from: arguments, keys: keys) {
            return date
        }
        let joinedKeys = keys.joined(separator: ", ")
        throw ComputerActionError.invalidArguments("Provide a valid ISO-8601 date for one of: \(joinedKeys).")
    }

    static func parseOptionalDate(from arguments: [String: String], keys: [String]) throws -> Date? {
        for key in keys {
            guard let rawValue = arguments[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawValue.isEmpty
            else {
                continue
            }

            if let parsed = makeISOFormatter(includeFractionalSeconds: true).date(from: rawValue) {
                return parsed
            }

            if let parsed = makeISOFormatter(includeFractionalSeconds: false).date(from: rawValue) {
                return parsed
            }

            throw ComputerActionError.invalidArguments("Invalid date for `\(key)`: \(rawValue)")
        }
        return nil
    }

    static func optionalText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parseBool(_ value: String?) -> Bool {
        parseOptionalBool(value) ?? false
    }

    static func parseOptionalBool(_ value: String?) -> Bool? {
        guard let value else {
            return nil
        }
        return switch value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "1", "true", "yes", "y", "on":
            true
        case "0", "false", "no", "n", "off":
            false
        default:
            nil
        }
    }
}
