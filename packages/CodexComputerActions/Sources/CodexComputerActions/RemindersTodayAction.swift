import CodexChatCore
import Foundation
#if canImport(EventKit)
    import EventKit
#endif

public struct ReminderItem: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let listName: String
    public let dueAt: Date?

    public init(id: String, title: String, listName: String, dueAt: Date?) {
        self.id = id
        self.title = title
        self.listName = listName
        self.dueAt = dueAt
    }
}

public protocol ReminderItemSource: Sendable {
    func reminders(from start: Date, to end: Date) async throws -> [ReminderItem]
}

public final class RemindersTodayAction: ComputerActionProvider {
    private let reminderSource: any ReminderItemSource
    private let nowProvider: @Sendable () -> Date

    public init(
        reminderSource: (any ReminderItemSource)? = nil,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.reminderSource = reminderSource ?? EventKitReminderItemSource()
        self.nowProvider = nowProvider
    }

    public let actionID = "reminders.today"
    public let displayName = "Reminders Today"
    public let safetyLevel: ComputerActionSafetyLevel = .readOnly
    public let requiresConfirmation = false

    public func preview(request: ComputerActionRequest) async throws -> ComputerActionPreviewArtifact {
        let now = nowProvider()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let hours = Int(request.arguments["rangeHours"] ?? "24") ?? 24
        let clampedHours = max(1, min(168, hours))
        let end = calendar.date(byAdding: .hour, value: clampedHours, to: dayStart)
            ?? dayStart.addingTimeInterval(86400)

        let reminders = try await reminderSource.reminders(from: dayStart, to: end)
        let sorted = reminders.sorted { lhs, rhs in
            switch (lhs.dueAt, rhs.dueAt) {
            case let (.some(left), .some(right)) where left != right:
                left < right
            case (.some, .none):
                true
            case (.none, .some):
                false
            default:
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let details: String = if sorted.isEmpty {
            "No reminders due in the selected range."
        } else {
            sorted.map { reminder in
                if let dueAt = reminder.dueAt {
                    return "- **\(reminder.title)** (due \(formatter.string(from: dueAt))) — \(reminder.listName)"
                }
                return "- **\(reminder.title)** (no due time) — \(reminder.listName)"
            }.joined(separator: "\n")
        }

        let summary = sorted.isEmpty
            ? "No reminders due in range."
            : "Found \(sorted.count) reminder(s)."

        return ComputerActionPreviewArtifact(
            actionID: actionID,
            runContextID: request.runContextID,
            title: "Reminders Overview",
            summary: summary,
            detailsMarkdown: details,
            data: [
                "reminders": Self.encodeReminders(sorted),
                "rangeHours": String(clampedHours),
            ]
        )
    }

    public func execute(
        request: ComputerActionRequest,
        preview: ComputerActionPreviewArtifact
    ) async throws -> ComputerActionExecutionResult {
        try validate(preview: preview, request: request)
        let reminders = Self.decodeReminders(preview.data["reminders"])
        let summary = reminders.isEmpty
            ? "Reminders check completed with no due reminders."
            : "Reminders check completed with \(reminders.count) reminder(s)."

        return ComputerActionExecutionResult(
            actionID: actionID,
            runContextID: request.runContextID,
            summary: summary,
            detailsMarkdown: preview.detailsMarkdown
        )
    }

    private static func encodeReminders(_ reminders: [ReminderItem]) -> String {
        guard let data = try? JSONEncoder().encode(reminders),
              let text = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return text
    }

    private static func decodeReminders(_ text: String?) -> [ReminderItem] {
        guard let text,
              let data = text.data(using: .utf8),
              let reminders = try? JSONDecoder().decode([ReminderItem].self, from: data)
        else {
            return []
        }
        return reminders
    }
}

public final class EventKitReminderItemSource: ReminderItemSource {
    public init() {}

    public func reminders(from start: Date, to end: Date) async throws -> [ReminderItem] {
        #if canImport(EventKit)
            let store = EKEventStore()
            let granted = try await requestAccess(store: store)
            guard granted else {
                throw Self.permissionDeniedError()
            }

            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: start,
                ending: end,
                calendars: nil
            )

            return try await fetchReminders(
                store: store,
                predicate: predicate,
                start: start,
                end: end
            )
        #else
            throw ComputerActionError.unsupported("Reminders access is unavailable on this platform.")
        #endif
    }

    #if canImport(EventKit)
        @available(macOS 14.0, *)
        private func requestAccessV14(store: EKEventStore) async throws -> Bool {
            try await store.requestFullAccessToReminders()
        }

        private func requestAccess(store: EKEventStore) async throws -> Bool {
            do {
                if #available(macOS 14.0, *) {
                    return try await requestAccessV14(store: store)
                }

                return try await withCheckedThrowingContinuation { continuation in
                    store.requestAccess(to: .reminder) { granted, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            } catch {
                if Self.isPermissionError(error) {
                    throw Self.permissionDeniedError()
                }
                throw ComputerActionError.executionFailed(
                    "Failed to request reminders access: \(error.localizedDescription)"
                )
            }
        }

        private func fetchReminders(
            store: EKEventStore,
            predicate: NSPredicate,
            start: Date,
            end: Date
        ) async throws -> [ReminderItem] {
            await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { reminders in
                    let mapped = (reminders ?? []).compactMap { reminder -> ReminderItem? in
                        let dueDate = reminder.dueDateComponents?.date
                        if let dueDate,
                           dueDate < start || dueDate > end
                        {
                            return nil
                        }

                        let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return ReminderItem(
                            id: reminder.calendarItemIdentifier,
                            title: title.isEmpty ? "Untitled Reminder" : title,
                            listName: reminder.calendar.title,
                            dueAt: dueDate
                        )
                    }
                    continuation.resume(returning: mapped)
                }
            }
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

        private static func permissionDeniedError() -> ComputerActionError {
            .permissionDenied(
                "Reminders access is denied. Enable Reminders permissions in System Settings > Privacy & Security > Reminders."
            )
        }
    #endif
}
