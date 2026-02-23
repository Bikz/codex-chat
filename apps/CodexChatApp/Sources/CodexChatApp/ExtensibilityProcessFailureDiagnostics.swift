import CodexExtensions
import CodexMods
import CodexSkills
import Foundation

extension AppModel {
    private static let extensibilityDiagnosticsLimit = 100

    struct ExtensibilityProcessFailureDetails: Hashable, Sendable {
        enum Kind: String, Hashable, Sendable {
            case timeout
            case truncatedOutput
            case launch
            case protocolViolation
            case command

            var label: String {
                switch self {
                case .timeout:
                    "timeout"
                case .truncatedOutput:
                    "output limit"
                case .launch:
                    "launch"
                case .protocolViolation:
                    "protocol"
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
        switch error {
        case let SkillCatalogError.commandFailed(command, output):
            return details(command: command, output: output)
        case let ModInstallServiceError.commandFailed(command, output):
            return details(command: command, output: output)
        case let ExtensionWorkerRunnerError.timedOut(timeoutMs):
            return ExtensibilityProcessFailureDetails(
                kind: .timeout,
                command: "extension-worker",
                summary: "Timed out after \(timeoutMs)ms."
            )
        case let ExtensionWorkerRunnerError.outputTooLarge(maxBytes):
            return ExtensibilityProcessFailureDetails(
                kind: .truncatedOutput,
                command: "extension-worker",
                summary: "Output exceeded \(maxBytes) bytes."
            )
        case let ExtensionWorkerRunnerError.launchFailed(message):
            return ExtensibilityProcessFailureDetails(
                kind: .launch,
                command: "extension-worker",
                summary: normalizedProcessSummary(message)
            )
        case let ExtensionWorkerRunnerError.nonZeroExit(code, stderr):
            let summary = normalizedProcessSummary(
                stderr.isEmpty ? "Worker exited with status \(code)." : stderr
            )
            return ExtensibilityProcessFailureDetails(
                kind: .command,
                command: "extension-worker",
                summary: summary
            )
        case let ExtensionWorkerRunnerError.malformedOutput(detail):
            return ExtensibilityProcessFailureDetails(
                kind: .protocolViolation,
                command: "extension-worker",
                summary: normalizedProcessSummary(detail)
            )
        case LaunchdManagerError.plistEncodingFailed:
            return ExtensibilityProcessFailureDetails(
                kind: .protocolViolation,
                command: "launchctl",
                summary: "Failed to encode launchd plist."
            )
        case let LaunchdManagerError.commandFailed(message):
            return details(command: "launchctl", output: message)
        case ExtensionWorkerRunnerError.invalidCommand:
            return ExtensibilityProcessFailureDetails(
                kind: .command,
                command: "extension-worker",
                summary: "Extension handler command is empty."
            )
        default:
            return nil
        }
    }

    func recordExtensibilityDiagnostic(
        surface: String,
        operation: String,
        details: ExtensibilityProcessFailureDetails
    ) {
        extensibilityDiagnostics.insert(
            ExtensibilityDiagnosticEvent(
                surface: surface,
                operation: operation,
                kind: details.kind.rawValue,
                command: details.command,
                summary: details.summary
            ),
            at: 0
        )
        if extensibilityDiagnostics.count > Self.extensibilityDiagnosticsLimit {
            extensibilityDiagnostics.removeLast(extensibilityDiagnostics.count - Self.extensibilityDiagnosticsLimit)
        }
    }

    private static func details(command: String, output: String) -> ExtensibilityProcessFailureDetails {
        ExtensibilityProcessFailureDetails(
            kind: classifyKind(for: output),
            command: command,
            summary: normalizedProcessSummary(output)
        )
    }

    private static func classifyKind(for output: String) -> ExtensibilityProcessFailureDetails.Kind {
        let lowercasedOutput = output.lowercased()
        if lowercasedOutput.contains("timed out after") {
            return .timeout
        }
        if lowercasedOutput.contains("[output truncated after") {
            return .truncatedOutput
        }
        if lowercasedOutput.contains("failed to launch process") {
            return .launch
        }
        if lowercasedOutput.contains("malformed output") {
            return .protocolViolation
        }
        return .command
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
