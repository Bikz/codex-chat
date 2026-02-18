import AppKit
import CodexChatInfra
import CodexChatUI
import CodexKit
import CodexSkills
import SwiftUI

@main
struct CodexChatApplication: App {
    @StateObject private var model: AppModel

    init() {
        // SwiftPM executable runs can have no main bundle identifier; disable
        // automatic tab indexing to avoid AppKit tab-index warnings.
        NSWindow.allowsAutomaticWindowTabbing = false
        let bootstrap = Self.bootstrapModel()
        _model = StateObject(wrappedValue: bootstrap)
    }

    var body: some Scene {
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

    @MainActor
    private static func bootstrapModel() -> AppModel {
        let storagePaths = CodexChatStoragePaths.current()

        do {
            try storagePaths.ensureRootStructure()
            try CodexChatStorageMigrationCoordinator.performInitialMigrationIfNeeded(paths: storagePaths)

            let database = try MetadataDatabase(databaseURL: storagePaths.metadataDatabaseURL)
            let repositories = MetadataRepositories(database: database)

            let skillCatalogService = SkillCatalogService(
                codexHomeURL: storagePaths.codexHomeURL,
                agentsHomeURL: storagePaths.agentsHomeURL
            )
            let runtime = CodexRuntime(
                environmentOverrides: [
                    "CODEX_HOME": storagePaths.codexHomeURL.path,
                ]
            )
            return AppModel(
                repositories: repositories,
                runtime: runtime,
                bootError: nil,
                skillCatalogService: skillCatalogService,
                storagePaths: storagePaths
            )
        } catch {
            return AppModel(
                repositories: nil,
                runtime: nil,
                bootError: error.localizedDescription,
                storagePaths: storagePaths
            )
        }
    }
}

private struct MainAppRoot: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ContentView(model: model)
            .designTokens(resolvedTokens)
            .background(WindowAccessor())
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                model.cancelPendingChatGPTLoginForTeardown()
            }
    }

    private var resolvedTokens: DesignTokens {
        let baseline: DesignTokens = colorScheme == .dark ? .systemDark : .systemLight
        let override = colorScheme == .dark ? model.effectiveDarkThemeOverride : model.effectiveThemeOverride
        return baseline.applying(override: override)
    }
}

// MARK: - Window accessor to ensure resizable style mask

private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.styleMask.insert(.resizable)
                window.minSize = NSSize(width: 600, height: 400)
                // Don't cap maxSize — let the user go full-screen or any size
                window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}

private struct SettingsRoot: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsView(model: model)
            .designTokens(resolvedTokens)
    }

    private var resolvedTokens: DesignTokens {
        let baseline: DesignTokens = colorScheme == .dark ? .systemDark : .systemLight
        let override = colorScheme == .dark ? model.effectiveDarkThemeOverride : model.effectiveThemeOverride
        return baseline.applying(override: override)
    }
}
