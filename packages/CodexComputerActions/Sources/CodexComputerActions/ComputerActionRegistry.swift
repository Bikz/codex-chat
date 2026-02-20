import Foundation

public struct ComputerActionRegistry: Sendable {
    public let desktopCleanup: DesktopCleanupAction
    public let calendarToday: CalendarTodayAction
    public let remindersToday: RemindersTodayAction
    public let messagesSend: MessagesSendAction
    public let appleScriptRun: AppleScriptRunAction

    public init(
        desktopCleanup: DesktopCleanupAction = DesktopCleanupAction(),
        calendarToday: CalendarTodayAction = CalendarTodayAction(),
        remindersToday: RemindersTodayAction = RemindersTodayAction(),
        messagesSend: MessagesSendAction = MessagesSendAction(),
        appleScriptRun: AppleScriptRunAction = AppleScriptRunAction()
    ) {
        self.desktopCleanup = desktopCleanup
        self.calendarToday = calendarToday
        self.remindersToday = remindersToday
        self.messagesSend = messagesSend
        self.appleScriptRun = appleScriptRun
    }

    public var allProviders: [any ComputerActionProvider] {
        [desktopCleanup, calendarToday, remindersToday, messagesSend, appleScriptRun]
    }

    public func provider(for actionID: String) -> (any ComputerActionProvider)? {
        allProviders.first(where: { $0.actionID == actionID })
    }
}
