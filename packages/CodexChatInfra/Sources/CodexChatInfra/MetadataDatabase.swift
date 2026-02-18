import Foundation
import GRDB

public final class MetadataDatabase: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public init(databaseURL: URL) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        self.dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try Self.migrator.migrate(dbQueue)
    }

    public static func appSupportDatabaseURL(
        fileManager: FileManager = .default,
        bundleIdentifier: String = "app.codexchat"
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = base.appendingPathComponent("CodexChat", isDirectory: true)
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory.appendingPathComponent("metadata.sqlite", isDirectory: false)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_metadata_tables") { db in
            try db.create(table: "projects") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("name", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "threads") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("projectId", .text).notNull()
                    .references("projects", onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(index: "idx_threads_project_id", on: "threads", columns: ["projectId"])

            try db.create(table: "preferences") { table in
                table.column("key", .text).notNull().primaryKey()
                table.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v2_add_runtime_thread_mappings") { db in
            try db.create(table: "runtime_thread_mappings") { table in
                table.column("localThreadID", .text).notNull().primaryKey()
                    .references("threads", onDelete: .cascade)
                table.column("runtimeThreadID", .text).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(
                index: "idx_runtime_thread_mappings_runtime_id",
                on: "runtime_thread_mappings",
                columns: ["runtimeThreadID"],
                unique: true
            )
        }

        migrator.registerMigration("v3_add_project_secrets") { db in
            try db.create(table: "project_secrets") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("projectID", .text).notNull()
                    .references("projects", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("keychainAccount", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(
                index: "idx_project_secrets_project_name",
                on: "project_secrets",
                columns: ["projectID", "name"],
                unique: true
            )
        }

        migrator.registerMigration("v4_add_project_paths_and_trust_state") { db in
            try db.alter(table: "projects") { table in
                table.add(column: "path", .text).notNull().defaults(to: "")
                table.add(column: "trustState", .text).notNull().defaults(to: "untrusted")
            }
            try db.create(index: "idx_projects_path", on: "projects", columns: ["path"])
        }

        migrator.registerMigration("v5_add_chat_search_index") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE chat_search_index USING fts5(
                    threadID UNINDEXED,
                    projectID UNINDEXED,
                    source UNINDEXED,
                    content
                )
                """)
        }

        return migrator
    }
}
