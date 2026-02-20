import Foundation

public struct ComputerActionRegistry: Sendable {
    public let desktopCleanup: DesktopCleanupAction
    public let calendarToday: CalendarTodayAction
    public let calendarCreate: CalendarCreateAction
    public let calendarUpdate: CalendarUpdateAction
    public let calendarDelete: CalendarDeleteAction
    public let remindersToday: RemindersTodayAction
    public let messagesSend: MessagesSendAction
    public let appleScriptRun: AppleScriptRunAction
    public let filesRead: FilesReadAction
    public let filesMove: FilesMoveAction

    public init(
        desktopCleanup: DesktopCleanupAction = DesktopCleanupAction(),
        calendarToday: CalendarTodayAction = CalendarTodayAction(),
        calendarCreate: CalendarCreateAction = CalendarCreateAction(),
        calendarUpdate: CalendarUpdateAction = CalendarUpdateAction(),
        calendarDelete: CalendarDeleteAction = CalendarDeleteAction(),
        remindersToday: RemindersTodayAction = RemindersTodayAction(),
        messagesSend: MessagesSendAction = MessagesSendAction(),
        appleScriptRun: AppleScriptRunAction = AppleScriptRunAction(),
        filesRead: FilesReadAction = FilesReadAction(),
        filesMove: FilesMoveAction = FilesMoveAction()
    ) {
        self.desktopCleanup = desktopCleanup
        self.calendarToday = calendarToday
        self.calendarCreate = calendarCreate
        self.calendarUpdate = calendarUpdate
        self.calendarDelete = calendarDelete
        self.remindersToday = remindersToday
        self.messagesSend = messagesSend
        self.appleScriptRun = appleScriptRun
        self.filesRead = filesRead
        self.filesMove = filesMove
    }

    public var allProviders: [any ComputerActionProvider] {
        [
            desktopCleanup,
            calendarToday,
            calendarCreate,
            calendarUpdate,
            calendarDelete,
            remindersToday,
            messagesSend,
            appleScriptRun,
            filesRead,
            filesMove,
        ]
    }

    public func provider(for actionID: String) -> (any ComputerActionProvider)? {
        allProviders.first(where: { $0.actionID == actionID })
    }
}
