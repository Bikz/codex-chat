import AppKit
import CodexChatUI
import SwiftUI

public struct CodexChatDesktopScene: Scene {
    @StateObject private var model: AppModel

    public init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        _model = StateObject(wrappedValue: CodexChatBootstrap.bootstrapModel())
    }

    public var body: some Scene {
        WindowGroup {
            MainAppRoot(model: model)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
        Settings {
            SettingsRoot(model: model)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Project…") {
                    model.presentNewProjectSheet()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("New Thread") {
                    model.createThread()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Show Skills & Mods") {
                    model.openSkillsAndMods()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            CommandMenu("Developer") {
                Button("Toggle Diagnostics") {
                    model.toggleDiagnostics()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Button("Toggle Shell Workspace") {
                    model.toggleShellWorkspace()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }
        }
    }
}

private struct MainAppRoot: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ContentView(model: model)
            .designTokens(resolvedTokens)
            .background(WindowAccessor(isTransparent: model.isTransparentThemeMode))
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                model.cancelPendingChatGPTLoginForTeardown()
            }
    }

    private var resolvedTokens: DesignTokens {
        let baseline: DesignTokens = colorScheme == .dark ? .systemDark : .systemLight
        let override = colorScheme == .dark ? model.resolvedDarkThemeOverride : model.resolvedLightThemeOverride
        return baseline.applying(override: override)
    }
}

// MARK: - Window accessor to ensure resizable style mask

private struct WindowAccessor: NSViewRepresentable {
    let isTransparent: Bool

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        window.styleMask.insert(.resizable)
        window.minSize = NSSize(width: 600, height: 400)
        // Don't cap maxSize — let the user go full-screen or any size
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if isTransparent {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
        } else {
            window.styleMask.remove(.fullSizeContentView)
            window.titlebarAppearsTransparent = false
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor
        }
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }

        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.toolbar?.showsBaselineSeparator = false
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

private struct SettingsRoot: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsView(model: model)
            .designTokens(resolvedTokens)
            .background(SettingsWindowAccessor())
    }

    private var resolvedTokens: DesignTokens {
        let baseline: DesignTokens = colorScheme == .dark ? .systemDark : .systemLight
        let override = colorScheme == .dark ? model.resolvedDarkThemeOverride : model.resolvedLightThemeOverride
        return baseline.applying(override: override)
    }
}
