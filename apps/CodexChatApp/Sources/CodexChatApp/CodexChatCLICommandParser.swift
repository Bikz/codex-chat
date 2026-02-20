import Foundation

public struct CodexChatCLIReproOptions: Equatable, Sendable {
    public var fixtureName: String
    public var fixturesRootOverride: String?

    public init(fixtureName: String, fixturesRootOverride: String?) {
        self.fixtureName = fixtureName
        self.fixturesRootOverride = fixturesRootOverride
    }
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
