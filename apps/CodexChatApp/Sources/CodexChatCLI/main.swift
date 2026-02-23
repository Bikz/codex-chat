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
        let command = try CodexChatCLICommandParser.parse(arguments: arguments)
        switch command {
        case .doctor:
            runDoctor()
        case .smoke:
            try runSmoke()
        case let .repro(options):
            try runRepro(options: options)
        case let .replay(options):
            try runReplay(options: options)
        case let .ledger(ledgerCommand):
            try runLedger(ledgerCommand)
        case let .policy(policyCommand):
            try runPolicy(policyCommand)
        case let .mod(modCommand):
            try runMod(modCommand)
        case .help:
            printUsage()
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
        let codexPath = summary.codexExecutablePath ?? "not found"
        print("Smoke check passed")
        print("Storage root: \(summary.storageRootPath)")
        print("Metadata database: \(summary.metadataDatabasePath)")
        print("Codex CLI: \(codexPath)")
    }

    private static func runRepro(options: CodexChatCLIReproOptions) throws {
        let fileManager = FileManager.default
        let fixturesRootURL: URL
        if let fixturesRootOverride = options.fixturesRootOverride {
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
            named: options.fixtureName,
            fixturesRoot: fixturesRootURL,
            fileManager: fileManager
        )

        print("Repro fixture passed: \(summary.fixtureName)")
        print("Transcript length: \(summary.transcriptLength)")
        print("Action count: \(summary.actionCount)")
        print("Final status: \(summary.finalStatus)")
    }

    private static func runReplay(options: CodexChatCLIReplayOptions) throws {
        guard let threadID = UUID(uuidString: options.threadID) else {
            throw CLIError("`--thread-id` must be a valid UUID")
        }

        let summary = try CodexChatBootstrap.replayThread(
            projectPath: options.projectPath,
            threadID: threadID,
            limit: options.limit
        )

        if options.asJSON {
            try printJSON(summary)
            return
        }

        print("Replay summary")
        print("Project: \(summary.projectPath)")
        print("Thread: \(summary.threadID.uuidString)")
        print("Turns: \(summary.turnCount) (completed=\(summary.completedTurnCount), pending=\(summary.pendingTurnCount), failed=\(summary.failedTurnCount))")

        for turn in summary.turns {
            print("- \(turn.timestamp.ISO8601Format()) [\(turn.status)] \(turn.turnID.uuidString)")
            if !turn.actions.isEmpty {
                for action in turn.actions {
                    print("  • action: \(action.method) :: \(action.title)")
                }
            }
        }
    }

    private static func runLedger(_ command: CodexChatCLILedgerCommand) throws {
        switch command {
        case let .export(options):
            guard let threadID = UUID(uuidString: options.threadID) else {
                throw CLIError("`--thread-id` must be a valid UUID")
            }

            let outputURL = options.outputPath.map { URL(fileURLWithPath: $0, isDirectory: false) }
            let summary = try CodexChatBootstrap.exportThreadLedger(
                projectPath: options.projectPath,
                threadID: threadID,
                limit: options.limit,
                outputURL: outputURL
            )

            print("Ledger export complete")
            print("Output: \(summary.outputPath)")
            print("Entries: \(summary.entryCount)")
            print("SHA256: \(summary.sha256)")
        }
    }

    private static func runPolicy(_ command: CodexChatCLIPolicyCommand) throws {
        switch command {
        case let .validate(options):
            let fileURL: URL
            if let filePath = options.filePath {
                fileURL = URL(fileURLWithPath: filePath, isDirectory: false)
            } else if let defaultURL = CodexChatBootstrap.defaultRuntimePolicyURL() {
                fileURL = defaultURL
            } else {
                throw CLIError("Unable to resolve default runtime policy file path; pass --file explicitly")
            }

            let report = try CodexChatBootstrap.validateRuntimePolicyDocument(at: fileURL)
            if report.isValid {
                print("Policy validation passed: \(report.filePath)")
            } else {
                print("Policy validation failed: \(report.filePath)")
            }

            if report.issues.isEmpty {
                print("No policy issues reported")
            } else {
                for issue in report.issues {
                    print("[\(issue.severity.uppercased())] \(issue.message)")
                }
            }

            if !report.isValid {
                throw CLIError("Policy validation failed")
            }
        }
    }

    private static func runMod(_ command: CodexChatCLIModCommand) throws {
        let result = try CodexChatCLIModRunner.run(command: command)
        for line in result.stdoutLines {
            print(line)
        }
        for line in result.stderrLines {
            fputs("\(line)\n", stderr)
        }
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
          replay --project-path <path>      Replay archived thread turns from local artifacts.
                 --thread-id <uuid>
               [--limit <n>] [--json]
          ledger export --project-path <path>
                 --thread-id <uuid>         Export thread event ledger JSON.
               [--limit <n>] [--output <path>]
          policy validate [--file <path>]   Validate runtime policy-as-code document.
          mod init --name <name>            Create a sample mod package.
               [--output <path>]
          mod validate --source <path|url>  Validate a local/GitHub mod source.
          mod inspect-source --source <path|url>
                                            Print structured source metadata as JSON.
        """)
    }

    private static func printJSON(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CLIError("Failed to encode JSON output")
        }
        print(json)
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
