import CodexChatInfra
import CodexChatUI
import CodexKit
import SwiftUI

@main
struct CodexChatApplication: App {
    @StateObject private var model: AppModel
    @StateObject private var themeProvider = ThemeProvider()

    init() {
        let bootstrap = Self.bootstrapModel()
        _model = StateObject(wrappedValue: bootstrap)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .designTokens(themeProvider.tokens)
                .onChange(of: model.effectiveThemeOverride) { override in
                    themeProvider.apply(override: override)
                }
        }
        Settings {
            SettingsView(model: model)
                .designTokens(themeProvider.tokens)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Project Folder…") {
                    model.openProjectFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("New Thread") {
                    model.createThread()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Show Skills") {
                    model.navigationSection = .skills
                    model.refreshSkillsSurface()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            CommandMenu("Developer") {
                Button("Toggle Diagnostics") {
                    model.toggleDiagnostics()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Button("Toggle Terminal / Logs") {
                    model.toggleLogsDrawer()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }
        }
    }

    @MainActor
    private static func bootstrapModel() -> AppModel {
        do {
            let databaseURL = try MetadataDatabase.appSupportDatabaseURL()
            let database = try MetadataDatabase(databaseURL: databaseURL)
            let repositories = MetadataRepositories(database: database)
            return AppModel(repositories: repositories, runtime: CodexRuntime(), bootError: nil)
        } catch {
            return AppModel(repositories: nil, runtime: nil, bootError: error.localizedDescription)
        }
    }
}
