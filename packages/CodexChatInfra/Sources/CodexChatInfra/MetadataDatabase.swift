import Foundation
import GRDB

public final class MetadataDatabase: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public init(databaseURL: URL) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try Self.migrator.migrate(dbQueue)
    }

    public static func appSupportDatabaseURL(
        fileManager: FileManager = .default,
        bundleIdentifier _: String = "app.codexchat"
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

        migrator.registerMigration("v6_add_project_safety_settings") { db in
            try db.alter(table: "projects") { table in
                table.add(column: "sandboxMode", .text).notNull().defaults(to: "read-only")
                table.add(column: "approvalPolicy", .text).notNull().defaults(to: "untrusted")
                table.add(column: "networkAccess", .boolean).notNull().defaults(to: false)
                table.add(column: "webSearch", .text).notNull().defaults(to: "cached")
            }

            // Keep existing trusted projects aligned with recommended defaults.
            try db.execute(
                sql: """
                UPDATE projects
                SET sandboxMode = 'workspace-write',
                    approvalPolicy = 'on-request',
                    networkAccess = 0,
                    webSearch = 'cached'
                WHERE trustState = 'trusted'
                """
            )
        }

        migrator.registerMigration("v7_add_project_skill_enablements") { db in
            try db.create(table: "project_skill_enablements") { table in
                table.column("projectID", .text).notNull()
                    .references("projects", onDelete: .cascade)
                table.column("skillPath", .text).notNull()
                table.column("enabled", .boolean).notNull().defaults(to: true)
                table.column("updatedAt", .datetime).notNull()
                table.primaryKey(["projectID", "skillPath"])
            }
            try db.create(
                index: "idx_project_skill_enablements_project",
                on: "project_skill_enablements",
                columns: ["projectID"]
            )
        }

        migrator.registerMigration("v8_add_project_memory_settings") { db in
            try db.alter(table: "projects") { table in
                table.add(column: "memoryWriteMode", .text).notNull().defaults(to: "off")
                table.add(column: "memoryEmbeddingsEnabled", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v9_add_project_ui_mod_path") { db in
            try db.alter(table: "projects") { table in
                table.add(column: "uiModPath", .text)
            }
        }

        migrator.registerMigration("v10_add_is_general_project") { db in
            try db.alter(table: "projects") { table in
                table.add(column: "isGeneralProject", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v11_add_follow_up_queue") { db in
            try db.create(table: "follow_up_queue") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("threadID", .text).notNull()
                    .references("threads", onDelete: .cascade)
                table.column("source", .text).notNull()
                table.column("dispatchMode", .text).notNull()
                table.column("state", .text).notNull()
                table.column("text", .text).notNull()
                table.column("sortIndex", .integer).notNull()
                table.column("originTurnID", .text)
                table.column("originSuggestionID", .text)
                table.column("lastError", .text)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_follow_up_queue_thread_sort",
                on: "follow_up_queue",
                columns: ["threadID", "sortIndex"]
            )
            try db.create(
                index: "idx_follow_up_queue_state_dispatch_created",
                on: "follow_up_queue",
                columns: ["state", "dispatchMode", "createdAt"]
            )
            try db.execute(
                sql: """
                CREATE UNIQUE INDEX idx_follow_up_queue_thread_origin_suggestion_unique
                ON follow_up_queue(threadID, originSuggestionID)
                WHERE originSuggestionID IS NOT NULL
                """
            )
        }

        migrator.registerMigration("v12_add_thread_pin_and_archive_state") { db in
            try db.alter(table: "threads") { table in
                table.add(column: "isPinned", .boolean).notNull().defaults(to: false)
                table.add(column: "archivedAt", .datetime)
            }
            try db.create(
                index: "idx_threads_archived_pinned_updated",
                on: "threads",
                columns: ["archivedAt", "isPinned", "updatedAt"]
            )
        }

        migrator.registerMigration("v13_add_extension_tables") { db in
            try db.create(table: "extension_installs") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("modID", .text).notNull()
                table.column("scope", .text).notNull()
                table.column("sourceURL", .text)
                table.column("installedPath", .text).notNull()
                table.column("enabled", .boolean).notNull().defaults(to: true)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_extension_installs_mod_scope", on: "extension_installs", columns: ["modID", "scope"], unique: true)

            try db.create(table: "extension_permissions") { table in
                table.column("modID", .text).notNull()
                table.column("permissionKey", .text).notNull()
                table.column("status", .text).notNull()
                table.column("grantedAt", .datetime).notNull()
                table.primaryKey(["modID", "permissionKey"])
            }

            try db.create(table: "extension_hook_state") { table in
                table.column("modID", .text).notNull()
                table.column("hookID", .text).notNull()
                table.column("lastRunAt", .datetime)
                table.column("lastStatus", .text).notNull()
                table.column("lastError", .text)
                table.primaryKey(["modID", "hookID"])
            }

            try db.create(table: "extension_automation_state") { table in
                table.column("modID", .text).notNull()
                table.column("automationID", .text).notNull()
                table.column("nextRunAt", .datetime)
                table.column("lastRunAt", .datetime)
                table.column("lastStatus", .text).notNull()
                table.column("lastError", .text)
                table.column("launchdLabel", .text)
                table.primaryKey(["modID", "automationID"])
            }
        }

        migrator.registerMigration("v14_add_skill_enablements") { db in
            try db.create(table: "skill_enablements") { table in
                table.column("target", .text).notNull()
                table.column("projectID", .text)
                table.column("skillPath", .text).notNull()
                table.column("enabled", .boolean).notNull().defaults(to: true)
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(
                index: "idx_skill_enablements_target_project",
                on: "skill_enablements",
                columns: ["target", "projectID"]
            )
            try db.execute(sql: """
            CREATE UNIQUE INDEX idx_skill_enablements_target_project_skill
            ON skill_enablements(target, IFNULL(projectID, ''), skillPath)
            """)
            try db.execute(sql: """
            INSERT INTO skill_enablements (target, projectID, skillPath, enabled, updatedAt)
            SELECT 'project', projectID, skillPath, enabled, updatedAt
            FROM project_skill_enablements
            """)
        }

        migrator.registerMigration("v15_scope_extension_installs_by_project") { db in
            try db.alter(table: "extension_installs") { table in
                table.add(column: "projectID", .text)
            }
            try db.execute(sql: "DROP INDEX IF EXISTS idx_extension_installs_mod_scope")
            try db.execute(sql: """
            CREATE UNIQUE INDEX idx_extension_installs_scope_project_mod
            ON extension_installs(scope, IFNULL(projectID, ''), modID)
            """)
            try db.create(
                index: "idx_extension_installs_scope_project_enabled",
                on: "extension_installs",
                columns: ["scope", "projectID", "enabled", "updatedAt"]
            )
        }

        migrator.registerMigration("v16_add_computer_actions_and_plan_runs") { db in
            try db.create(table: "computer_action_permissions") { table in
                table.column("actionID", .text).notNull()
                table.column("projectKey", .text).notNull()
                table.column("projectID", .text)
                table.column("decision", .text).notNull()
                table.column("decidedAt", .datetime).notNull()
                table.primaryKey(["actionID", "projectKey"])
            }
            try db.create(
                index: "idx_computer_action_permissions_project",
                on: "computer_action_permissions",
                columns: ["projectKey", "actionID"]
            )

            try db.create(table: "computer_action_runs") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("actionID", .text).notNull()
                table.column("runContextID", .text).notNull()
                table.column("threadID", .text)
                    .references("threads", onDelete: .cascade)
                table.column("projectID", .text)
                    .references("projects", onDelete: .cascade)
                table.column("phase", .text).notNull()
                table.column("status", .text).notNull()
                table.column("previewArtifact", .text)
                table.column("summary", .text)
                table.column("errorMessage", .text)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(
                index: "idx_computer_action_runs_context_updated",
                on: "computer_action_runs",
                columns: ["runContextID", "updatedAt"]
            )
            try db.create(
                index: "idx_computer_action_runs_thread_updated",
                on: "computer_action_runs",
                columns: ["threadID", "updatedAt"]
            )

            try db.create(table: "plan_runs") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("threadID", .text).notNull()
                    .references("threads", onDelete: .cascade)
                table.column("projectID", .text).notNull()
                    .references("projects", onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("sourcePath", .text)
                table.column("status", .text).notNull()
                table.column("totalTasks", .integer).notNull().defaults(to: 0)
                table.column("completedTasks", .integer).notNull().defaults(to: 0)
                table.column("lastError", .text)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(
                index: "idx_plan_runs_thread_updated",
                on: "plan_runs",
                columns: ["threadID", "updatedAt"]
            )

            try db.create(table: "plan_run_tasks") { table in
                table.column("planRunID", .text).notNull()
                    .references("plan_runs", onDelete: .cascade)
                table.column("taskID", .text).notNull()
                table.column("title", .text).notNull()
                table.column("dependencyIDs", .text).notNull()
                table.column("status", .text).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.primaryKey(["planRunID", "taskID"])
            }
            try db.create(
                index: "idx_plan_run_tasks_plan_status",
                on: "plan_run_tasks",
                columns: ["planRunID", "status"]
            )
        }

        return migrator
    }
}
