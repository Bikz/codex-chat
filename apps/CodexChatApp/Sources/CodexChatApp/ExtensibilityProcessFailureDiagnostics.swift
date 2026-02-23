import CodexMods
import CodexSkills
import Foundation

extension AppModel {
    struct ExtensibilityProcessFailureDetails: Hashable, Sendable {
        enum Kind: String, Hashable, Sendable {
            case timeout
            case truncatedOutput
            case launch
            case command

            var label: String {
                switch self {
                case .timeout:
                    "timeout"
                case .truncatedOutput:
                    "output limit"
                case .launch:
                    "launch"
                case .command:
                    "command"
                }
            }
        }

        let kind: Kind
        let command: String
        let summary: String
    }

    static func extensibilityProcessFailureDetails(from error: Error) -> ExtensibilityProcessFailureDetails? {
        let commandOutput: (command: String, output: String)?
        switch error {
        case let SkillCatalogError.commandFailed(command, output):
            commandOutput = (command, output)
        case let ModInstallServiceError.commandFailed(command, output):
            commandOutput = (command, output)
        default:
            commandOutput = nil
        }

        guard let commandOutput else {
            return nil
        }

        let lowercasedOutput = commandOutput.output.lowercased()
        let kind: ExtensibilityProcessFailureDetails.Kind
        if lowercasedOutput.contains("timed out after") {
            kind = .timeout
        } else if lowercasedOutput.contains("[output truncated after") {
            kind = .truncatedOutput
        } else if lowercasedOutput.contains("failed to launch process") {
            kind = .launch
        } else {
            kind = .command
        }

        let summary = normalizedProcessSummary(commandOutput.output)
        return ExtensibilityProcessFailureDetails(
            kind: kind,
            command: commandOutput.command,
            summary: summary
        )
    }

    private static func normalizedProcessSummary(_ output: String, maxLength: Int = 220) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No process output captured."
        }

        let firstLine = trimmed
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .first ?? trimmed
        if firstLine.count <= maxLength {
            return firstLine
        }
        let endIndex = firstLine.index(firstLine.startIndex, offsetBy: maxLength)
        return "\(firstLine[..<endIndex])..."
    }
}
