import AppKit
import CodexChatUI
import Foundation
import SwiftUI

@MainActor
func configureDesktopWindow(_ window: NSWindow, isTransparent: Bool) {
    if !window.styleMask.contains(.resizable) {
        window.styleMask.insert(.resizable)
    }
    let minSize = NSSize(width: 600, height: 400)
    if window.minSize != minSize {
        window.minSize = minSize
    }

    // Don't cap maxSize — let the user go full-screen or any size.
    let maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    if window.maxSize != maxSize {
        window.maxSize = maxSize
    }
    if !window.styleMask.contains(.fullSizeContentView) {
        window.styleMask.insert(.fullSizeContentView)
    }
    if window.toolbarStyle != .unified {
        window.toolbarStyle = .unified
    }
    if window.toolbar?.showsBaselineSeparator != false {
        window.toolbar?.showsBaselineSeparator = false
    }
    if window.titleVisibility != .hidden {
        window.titleVisibility = .hidden
    }
    if !window.titlebarAppearsTransparent {
        window.titlebarAppearsTransparent = true
    }
    if window.titlebarSeparatorStyle != .none {
        window.titlebarSeparatorStyle = .none
    }

    let shouldBeOpaque = !isTransparent
    if window.isOpaque != shouldBeOpaque {
        window.isOpaque = shouldBeOpaque
    }
    let targetBackgroundColor = isTransparent ? NSColor.clear : NSColor.windowBackgroundColor
    if window.backgroundColor != targetBackgroundColor {
        window.backgroundColor = targetBackgroundColor
    }
}

@MainActor
func configureSettingsWindow(_ window: NSWindow, isTransparent: Bool) {
    if !window.styleMask.contains(.fullSizeContentView) {
        window.styleMask.insert(.fullSizeContentView)
    }
    if window.titleVisibility != .hidden {
        window.titleVisibility = .hidden
    }
    if !window.titlebarAppearsTransparent {
        window.titlebarAppearsTransparent = true
    }
    if window.titlebarSeparatorStyle != .none {
        window.titlebarSeparatorStyle = .none
    }
    if window.toolbarStyle != .unified {
        window.toolbarStyle = .unified
    }
    if window.toolbar?.showsBaselineSeparator != false {
        window.toolbar?.showsBaselineSeparator = false
    }

    let shouldBeOpaque = !isTransparent
    if window.isOpaque != shouldBeOpaque {
        window.isOpaque = shouldBeOpaque
    }
    let targetBackgroundColor = isTransparent ? NSColor.clear : NSColor.windowBackgroundColor
    if window.backgroundColor != targetBackgroundColor {
        window.backgroundColor = targetBackgroundColor
    }
}

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
        .windowStyle(.hiddenTitleBar)
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
            .glassSurfacesEnabled(model.isTransparentThemeMode)
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

    final class Coordinator {
        weak var configuredWindow: NSWindow?
        var lastTransparentValue: Bool?
        var pendingConfigTask: Task<Void, Never>?

        deinit {
            pendingConfigTask?.cancel()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleWindowConfiguration(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleWindowConfiguration(for: nsView, coordinator: context.coordinator)
    }

    private func scheduleWindowConfiguration(for view: NSView, coordinator: Coordinator) {
        coordinator.pendingConfigTask?.cancel()
        coordinator.pendingConfigTask = Task { @MainActor [weak view, weak coordinator] in
            // Defer until after the current SwiftUI/AppKit layout cycle to avoid layout recursion.
            await Task.yield()
            guard !Task.isCancelled else { return }
            DispatchQueue.main.async {
                guard let view, let coordinator else { return }
                configureWindow(for: view, coordinator: coordinator)
            }
        }
    }

    private func configureWindow(for view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }
        let hasWindowChanged = coordinator.configuredWindow !== window
        let hasTransparencyChanged = coordinator.lastTransparentValue != isTransparent
        guard hasWindowChanged || hasTransparencyChanged else { return }
        coordinator.configuredWindow = window
        coordinator.lastTransparentValue = isTransparent
        configureDesktopWindow(window, isTransparent: isTransparent)
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    let isTransparent: Bool

    final class Coordinator {
        weak var configuredWindow: NSWindow?
        var lastTransparentValue: Bool?
        var pendingConfigTask: Task<Void, Never>?

        deinit {
            pendingConfigTask?.cancel()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleWindowConfiguration(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleWindowConfiguration(for: nsView, coordinator: context.coordinator)
    }

    private func scheduleWindowConfiguration(for view: NSView, coordinator: Coordinator) {
        coordinator.pendingConfigTask?.cancel()
        coordinator.pendingConfigTask = Task { @MainActor [weak view, weak coordinator] in
            // Defer until after the current SwiftUI/AppKit layout cycle to avoid layout recursion.
            await Task.yield()
            guard !Task.isCancelled else { return }
            DispatchQueue.main.async {
                guard let view, let coordinator else { return }
                configureWindow(for: view, coordinator: coordinator)
            }
        }
    }

    private func configureWindow(for view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }
        let hasWindowChanged = coordinator.configuredWindow !== window
        let hasTransparencyChanged = coordinator.lastTransparentValue != isTransparent
        guard hasWindowChanged || hasTransparencyChanged else { return }
        coordinator.configuredWindow = window
        coordinator.lastTransparentValue = isTransparent
        configureSettingsWindow(window, isTransparent: isTransparent)
    }
}

private struct SettingsRoot: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsView(model: model)
            .designTokens(resolvedTokens)
            .glassSurfacesEnabled(model.isTransparentThemeMode)
            .background(SettingsWindowAccessor(isTransparent: model.isTransparentThemeMode))
    }

    private var resolvedTokens: DesignTokens {
        let baseline: DesignTokens = colorScheme == .dark ? .systemDark : .systemLight
        let override = colorScheme == .dark ? model.resolvedDarkThemeOverride : model.resolvedLightThemeOverride
        return baseline.applying(override: override)
    }
}
