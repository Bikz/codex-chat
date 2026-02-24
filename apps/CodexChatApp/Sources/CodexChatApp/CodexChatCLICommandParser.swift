import Foundation

public struct CodexChatCLIReproOptions: Equatable, Sendable {
    public var fixtureName: String
    public var fixturesRootOverride: String?

    public init(fixtureName: String, fixturesRootOverride: String?) {
        self.fixtureName = fixtureName
        self.fixturesRootOverride = fixturesRootOverride
    }
}

public struct CodexChatCLIReplayOptions: Equatable, Sendable {
    public var projectPath: String
    public var threadID: String
    public var limit: Int
    public var asJSON: Bool

    public init(projectPath: String, threadID: String, limit: Int, asJSON: Bool) {
        self.projectPath = projectPath
        self.threadID = threadID
        self.limit = limit
        self.asJSON = asJSON
    }
}

public struct CodexChatCLILedgerExportOptions: Equatable, Sendable {
    public var projectPath: String
    public var threadID: String
    public var limit: Int
    public var outputPath: String?

    public init(projectPath: String, threadID: String, limit: Int, outputPath: String?) {
        self.projectPath = projectPath
        self.threadID = threadID
        self.limit = limit
        self.outputPath = outputPath
    }
}

public struct CodexChatCLILedgerBackfillOptions: Equatable, Sendable {
    public var projectPath: String
    public var limit: Int
    public var force: Bool
    public var asJSON: Bool

    public init(projectPath: String, limit: Int, force: Bool, asJSON: Bool) {
        self.projectPath = projectPath
        self.limit = limit
        self.force = force
        self.asJSON = asJSON
    }
}

public enum CodexChatCLILedgerCommand: Equatable, Sendable {
    case export(CodexChatCLILedgerExportOptions)
    case backfill(CodexChatCLILedgerBackfillOptions)
}

public struct CodexChatCLIPolicyValidateOptions: Equatable, Sendable {
    public var filePath: String?

    public init(filePath: String?) {
        self.filePath = filePath
    }
}

public enum CodexChatCLIPolicyCommand: Equatable, Sendable {
    case validate(CodexChatCLIPolicyValidateOptions)
}

public enum CodexChatCLIModCommand: Equatable, Sendable {
    case validate(source: String)
    case inspectSource(source: String)
    case initSample(name: String, outputPath: String)
}

public enum CodexChatCLICommand: Equatable, Sendable {
    case doctor
    case smoke
    case repro(CodexChatCLIReproOptions)
    case replay(CodexChatCLIReplayOptions)
    case ledger(CodexChatCLILedgerCommand)
    case policy(CodexChatCLIPolicyCommand)
    case mod(CodexChatCLIModCommand)
    case help
}

public struct CodexChatCLIArgumentError: LocalizedError, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public enum CodexChatCLICommandParser {
    public static func parse(
        arguments: [String],
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) throws -> CodexChatCLICommand {
        guard let command = arguments.first else {
            return .help
        }

        switch command {
        case "doctor":
            return .doctor
        case "smoke":
            return .smoke
        case "repro":
            let options = try parseReproOptions(arguments: Array(arguments.dropFirst()))
            return .repro(options)
        case "replay":
            let options = try parseReplayOptions(arguments: Array(arguments.dropFirst()))
            return .replay(options)
        case "ledger":
            let subcommand = try parseLedgerCommand(arguments: Array(arguments.dropFirst()))
            return .ledger(subcommand)
        case "policy":
            let subcommand = try parsePolicyCommand(arguments: Array(arguments.dropFirst()))
            return .policy(subcommand)
        case "mod":
            let modCommand = try parseModCommand(
                arguments: Array(arguments.dropFirst()),
                currentDirectoryPath: currentDirectoryPath
            )
            return .mod(modCommand)
        case "help", "--help", "-h":
            return .help
        default:
            throw CodexChatCLIArgumentError("Unknown command: \(command). Run `CodexChatCLI help`.")
        }
    }

    private static func parseReproOptions(arguments: [String]) throws -> CodexChatCLIReproOptions {
        var fixtureName: String?
        var fixturesRootOverride: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--fixture":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --fixture")
                }
                fixtureName = arguments[index + 1]
                index += 2
            case "--fixtures-root":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --fixtures-root")
                }
                fixturesRootOverride = arguments[index + 1]
                index += 2
            default:
                throw CodexChatCLIArgumentError("Unknown repro option: \(argument)")
            }
        }

        guard let fixtureName,
              !fixtureName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexChatCLIArgumentError("`repro` requires --fixture <name>")
        }

        return CodexChatCLIReproOptions(fixtureName: fixtureName, fixturesRootOverride: fixturesRootOverride)
    }

    private static func parseReplayOptions(arguments: [String]) throws -> CodexChatCLIReplayOptions {
        var projectPath: String?
        var threadID: String?
        var limit = 100
        var asJSON = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--project-path":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --project-path")
                }
                projectPath = arguments[index + 1]
                index += 2
            case "--thread-id":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --thread-id")
                }
                threadID = arguments[index + 1]
                index += 2
            case "--limit":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --limit")
                }
                limit = try parsePositiveInt(arguments[index + 1], flag: "--limit")
                index += 2
            case "--json":
                asJSON = true
                index += 1
            default:
                throw CodexChatCLIArgumentError("Unknown replay option: \(argument)")
            }
        }

        guard let projectPath,
              !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexChatCLIArgumentError("`replay` requires --project-path <path>")
        }

        guard let threadID,
              !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexChatCLIArgumentError("`replay` requires --thread-id <uuid>")
        }

        return CodexChatCLIReplayOptions(projectPath: projectPath, threadID: threadID, limit: limit, asJSON: asJSON)
    }

    private static func parseLedgerCommand(arguments: [String]) throws -> CodexChatCLILedgerCommand {
        guard let subcommand = arguments.first else {
            throw CodexChatCLIArgumentError("`ledger` requires a subcommand: export, backfill")
        }

        switch subcommand {
        case "export":
            let options = try parseLedgerExportOptions(arguments: Array(arguments.dropFirst()))
            return .export(options)
        case "backfill":
            let options = try parseLedgerBackfillOptions(arguments: Array(arguments.dropFirst()))
            return .backfill(options)
        default:
            throw CodexChatCLIArgumentError("Unknown ledger subcommand: \(subcommand)")
        }
    }

    private static func parseLedgerExportOptions(arguments: [String]) throws -> CodexChatCLILedgerExportOptions {
        var projectPath: String?
        var threadID: String?
        var limit = 100
        var outputPath: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--project-path":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --project-path")
                }
                projectPath = arguments[index + 1]
                index += 2
            case "--thread-id":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --thread-id")
                }
                threadID = arguments[index + 1]
                index += 2
            case "--limit":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --limit")
                }
                limit = try parsePositiveInt(arguments[index + 1], flag: "--limit")
                index += 2
            case "--output":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --output")
                }
                outputPath = arguments[index + 1]
                index += 2
            default:
                throw CodexChatCLIArgumentError("Unknown ledger export option: \(argument)")
            }
        }

        guard let projectPath,
              !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexChatCLIArgumentError("`ledger export` requires --project-path <path>")
        }

        guard let threadID,
              !threadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexChatCLIArgumentError("`ledger export` requires --thread-id <uuid>")
        }

        return CodexChatCLILedgerExportOptions(
            projectPath: projectPath,
            threadID: threadID,
            limit: limit,
            outputPath: outputPath
        )
    }

    private static func parseLedgerBackfillOptions(arguments: [String]) throws -> CodexChatCLILedgerBackfillOptions {
        var projectPath: String?
        var limit = Int.max
        var force = false
        var asJSON = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--project-path":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --project-path")
                }
                projectPath = arguments[index + 1]
                index += 2
            case "--limit":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --limit")
                }
                limit = try parsePositiveInt(arguments[index + 1], flag: "--limit")
                index += 2
            case "--force":
                force = true
                index += 1
            case "--json":
                asJSON = true
                index += 1
            default:
                throw CodexChatCLIArgumentError("Unknown ledger backfill option: \(argument)")
            }
        }

        guard let projectPath,
              !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexChatCLIArgumentError("`ledger backfill` requires --project-path <path>")
        }

        return CodexChatCLILedgerBackfillOptions(
            projectPath: projectPath,
            limit: limit,
            force: force,
            asJSON: asJSON
        )
    }

    private static func parsePolicyCommand(arguments: [String]) throws -> CodexChatCLIPolicyCommand {
        guard let subcommand = arguments.first else {
            throw CodexChatCLIArgumentError("`policy` requires a subcommand: validate")
        }

        switch subcommand {
        case "validate":
            let options = try parsePolicyValidateOptions(arguments: Array(arguments.dropFirst()))
            return .validate(options)
        default:
            throw CodexChatCLIArgumentError("Unknown policy subcommand: \(subcommand)")
        }
    }

    private static func parsePolicyValidateOptions(arguments: [String]) throws -> CodexChatCLIPolicyValidateOptions {
        var filePath: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--file":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --file")
                }
                filePath = arguments[index + 1]
                index += 2
            default:
                throw CodexChatCLIArgumentError("Unknown policy validate option: \(argument)")
            }
        }

        return CodexChatCLIPolicyValidateOptions(filePath: filePath)
    }

    private static func parsePositiveInt(_ value: String, flag: String) throws -> Int {
        guard let parsed = Int(value), parsed > 0 else {
            throw CodexChatCLIArgumentError("\(flag) must be a positive integer")
        }
        return parsed
    }

    private static func parseModCommand(
        arguments: [String],
        currentDirectoryPath: String
    ) throws -> CodexChatCLIModCommand {
        guard let subcommand = arguments.first else {
            throw CodexChatCLIArgumentError("`mod` requires a subcommand: init, validate, or inspect-source")
        }

        let subcommandArguments = Array(arguments.dropFirst())
        switch subcommand {
        case "validate":
            let source = try parseSourceArgument(subcommandArguments, command: "mod validate")
            return .validate(source: source)
        case "inspect-source":
            let source = try parseSourceArgument(subcommandArguments, command: "mod inspect-source")
            return .inspectSource(source: source)
        case "init":
            return try parseModInit(arguments: subcommandArguments, currentDirectoryPath: currentDirectoryPath)
        default:
            throw CodexChatCLIArgumentError("Unknown mod subcommand: \(subcommand)")
        }
    }

    private static func parseSourceArgument(_ arguments: [String], command: String) throws -> String {
        var source: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--source":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --source")
                }
                source = arguments[index + 1]
                index += 2
            default:
                if source == nil, !argument.hasPrefix("-") {
                    source = argument
                    index += 1
                } else {
                    throw CodexChatCLIArgumentError("Unknown \(command) option: \(argument)")
                }
            }
        }

        guard let source,
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexChatCLIArgumentError("`\(command)` requires --source <path-or-url>")
        }

        return source
    }

    private static func parseModInit(
        arguments: [String],
        currentDirectoryPath: String
    ) throws -> CodexChatCLIModCommand {
        var name: String?
        var outputPath: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--name":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --name")
                }
                name = arguments[index + 1]
                index += 2
            case "--output":
                guard index + 1 < arguments.count else {
                    throw CodexChatCLIArgumentError("Missing value for --output")
                }
                outputPath = arguments[index + 1]
                index += 2
            default:
                throw CodexChatCLIArgumentError("Unknown mod init option: \(argument)")
            }
        }

        guard let name,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexChatCLIArgumentError("`mod init` requires --name <mod-name>")
        }

        let resolvedOutput = outputPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .initSample(
            name: name,
            outputPath: (resolvedOutput?.isEmpty == false ? resolvedOutput : currentDirectoryPath) ?? currentDirectoryPath
        )
    }
}
