import CodexChatInfra
import SwiftUI

@main
struct CodexChatApplication: App {
    @StateObject private var model: AppModel

    init() {
        let bootstrap = Self.bootstrapModel()
        _model = StateObject(wrappedValue: bootstrap)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Project") {
                    model.createProject()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("New Thread") {
                    model.createThread()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }

    @MainActor
    private static func bootstrapModel() -> AppModel {
        do {
            let databaseURL = try MetadataDatabase.appSupportDatabaseURL()
            let database = try MetadataDatabase(databaseURL: databaseURL)
            let repositories = MetadataRepositories(database: database)
            return AppModel(repositories: repositories, bootError: nil)
        } catch {
            return AppModel(repositories: nil, bootError: error.localizedDescription)
        }
    }
}
