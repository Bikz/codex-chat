import AppKit
import CodexChatShared
import SwiftUI

@main
struct CodexChatHostApp: App {
    @NSApplicationDelegateAdaptor(CodexChatHostAppDelegate.self) private var appDelegate

    var body: some Scene {
        CodexChatDesktopScene()
    }
}

final class CodexChatHostAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.activateAndFocusMainWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.activateAndFocusMainWindow()
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        activateAndFocusMainWindow()
        return true
    }

    private func activateAndFocusMainWindow() {
        let app = NSApplication.shared
        app.activate(ignoringOtherApps: true)

        guard let window = app.windows.first(where: { $0.canBecomeKey && ($0.isVisible || $0.isMiniaturized) })
            ?? app.windows.first(where: { $0.canBecomeKey })
            ?? app.mainWindow
        else {
            return
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }
}
