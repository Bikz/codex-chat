import Foundation

public struct ComputerActionRegistry: Sendable {
    public let desktopCleanup: DesktopCleanupAction
    public let calendarToday: CalendarTodayAction
    public let messagesSend: MessagesSendAction

    public init(
        desktopCleanup: DesktopCleanupAction = DesktopCleanupAction(),
        calendarToday: CalendarTodayAction = CalendarTodayAction(),
        messagesSend: MessagesSendAction = MessagesSendAction()
    ) {
        self.desktopCleanup = desktopCleanup
        self.calendarToday = calendarToday
        self.messagesSend = messagesSend
    }

    public var allProviders: [any ComputerActionProvider] {
        [desktopCleanup, calendarToday, messagesSend]
    }

    public func provider(for actionID: String) -> (any ComputerActionProvider)? {
        allProviders.first(where: { $0.actionID == actionID })
    }
}
