import CodexChatShared
import Foundation

@main
struct CodexChatCLI {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            let message = (error as NSError).localizedDescription
            fputs("error: \(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printUsage()
            return
        }

        switch command {
        case "doctor":
            runDoctor()
        case "smoke":
            try runSmoke()
        case "repro":
            try runRepro(arguments: Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            printUsage()
        default:
            throw CLIError("Unknown command: \(command). Run `CodexChatCLI help`.")
        }
    }

    private static func runDoctor() {
        let checks = CodexChatBootstrap.doctorChecks()
        for check in checks {
            let marker = switch check.status {
            case .ok:
                "OK"
            case .warning:
                "WARN"
            case .failed:
                "FAIL"
            }
            print("[\(marker)] \(check.title): \(check.detail)")
        }
    }

    private static func runSmoke() throws {
        let summary = try CodexChatBootstrap.runSmokeCheck()
        print("Smoke check passed")
        print("Storage root: \(summary.storageRootPath)")
        print("Metadata database: \(summary.metadataDatabasePath)")
        print("Codex CLI: \(summary.codexExecutablePath ?? "not found")")
    }

    private static func runRepro(arguments: [String]) throws {
        var fixtureName: String?
        var fixturesRootOverride: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--fixture":
                guard index + 1 < arguments.count else {
                    throw CLIError("Missing value for --fixture")
                }
                fixtureName = arguments[index + 1]
                index += 2
            case "--fixtures-root":
                guard index + 1 < arguments.count else {
                    throw CLIError("Missing value for --fixtures-root")
                }
                fixturesRootOverride = arguments[index + 1]
                index += 2
            default:
                throw CLIError("Unknown repro option: \(argument)")
            }
        }

        guard let fixtureName else {
            throw CLIError("`repro` requires --fixture <name>")
        }

        let fileManager = FileManager.default
        let fixturesRootURL: URL
        if let fixturesRootOverride {
            fixturesRootURL = URL(fileURLWithPath: fixturesRootOverride, isDirectory: true)
        } else {
            guard let repoRoot = discoverRepositoryRoot(fileManager: fileManager) else {
                throw CLIError("Unable to discover repository root for default fixture path")
            }
            fixturesRootURL = repoRoot
                .appendingPathComponent("apps", isDirectory: true)
                .appendingPathComponent("CodexChatApp", isDirectory: true)
                .appendingPathComponent("Fixtures", isDirectory: true)
                .appendingPathComponent("repro", isDirectory: true)
        }

        let summary = try CodexChatBootstrap.runReproFixture(
            named: fixtureName,
            fixturesRoot: fixturesRootURL,
            fileManager: fileManager
        )

        print("Repro fixture passed: \(summary.fixtureName)")
        print("Transcript length: \(summary.transcriptLength)")
        print("Action count: \(summary.actionCount)")
        print("Final status: \(summary.finalStatus)")
    }

    private static func discoverRepositoryRoot(fileManager: FileManager) -> URL? {
        var cursor = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true).standardizedFileURL
        let markerPath = "apps/CodexChatApp/Package.swift"

        while true {
            if fileManager.fileExists(atPath: cursor.appendingPathComponent(markerPath).path) {
                return cursor
            }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                return nil
            }
            cursor = parent
        }
    }

    private static func printUsage() {
        print("""
        CodexChatCLI commands:
          doctor                            Validate local prerequisites.
          smoke                             Run non-UI startup health checks.
          repro --fixture <name>            Run deterministic fixture replay.
               [--fixtures-root <path>]
        """)
    }
}

private struct CLIError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
