import CodexExtensions
import CodexMods
import CodexSkills
import Foundation

extension AppModel {
    private static let defaultExtensibilityDiagnosticsLimit = 100
    private static let minExtensibilityDiagnosticsLimit = 25
    private static let maxExtensibilityDiagnosticsLimit = 500

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

    struct ExtensibilityDiagnosticPlaybook: Hashable, Sendable {
        enum Shortcut: String, Hashable, Sendable {
            case openAppSettings
        }

        let headline: String
        let steps: [String]
        let suggestedCommand: String?
        let shortcut: Shortcut?

        var primaryStep: String {
            steps.first ?? headline
        }
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

    static func extensibilityDiagnosticPlaybook(
        for event: ExtensibilityDiagnosticEvent
    ) -> ExtensibilityDiagnosticPlaybook {
        switch ExtensibilityProcessFailureDetails.Kind(rawValue: event.kind) {
        case .timeout:
            ExtensibilityDiagnosticPlaybook(
                headline: "Retry with a narrower scope",
                steps: [
                    "Re-run the action after reducing payload size or splitting the task.",
                    "If this repeats, verify the worker command can complete locally within timeout.",
                ],
                suggestedCommand: nil,
                shortcut: nil
            )
        case .truncatedOutput:
            ExtensibilityDiagnosticPlaybook(
                headline: "Inspect full process output",
                steps: [
                    "Run `\(event.command)` manually to capture complete output.",
                    "Trim verbose logs in scripts so critical errors stay in the first lines.",
                ],
                suggestedCommand: event.command,
                shortcut: nil
            )
        case .launch:
            ExtensibilityDiagnosticPlaybook(
                headline: "Fix executable launch prerequisites",
                steps: [
                    "Confirm `\(event.command)` exists, is executable, and is reachable in PATH.",
                    "For mods/extensions, verify entrypoint paths and execute permissions.",
                ],
                suggestedCommand: event.command,
                shortcut: nil
            )
        case .protocolViolation:
            ExtensibilityDiagnosticPlaybook(
                headline: "Repair extension output contract",
                steps: [
                    "Ensure the first stdout line is valid JSON matching the extension worker schema.",
                    "Move extra diagnostics to stderr or later stdout lines.",
                ],
                suggestedCommand: nil,
                shortcut: nil
            )
        case .command:
            commandFailurePlaybook(for: event.command)
        case .none:
            ExtensibilityDiagnosticPlaybook(
                headline: "Collect command diagnostics",
                steps: [
                    "Capture the failing command output and validate permissions/source trust.",
                    "Retry after addressing environment preconditions.",
                ],
                suggestedCommand: nil,
                shortcut: nil
            )
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
        let retentionLimit = Self.normalizedDiagnosticsLimit(extensibilityDiagnosticsRetentionLimit)
        if extensibilityDiagnosticsRetentionLimit != retentionLimit {
            extensibilityDiagnosticsRetentionLimit = retentionLimit
        }
        if extensibilityDiagnostics.count > retentionLimit {
            extensibilityDiagnostics.removeLast(extensibilityDiagnostics.count - retentionLimit)
        }

        Task { [weak self] in
            guard let self else { return }
            await persistExtensibilityDiagnosticsIfNeeded()
        }
    }

    func setExtensibilityDiagnosticsRetentionLimit(_ limit: Int) {
        let normalized = Self.normalizedDiagnosticsLimit(limit)
        guard extensibilityDiagnosticsRetentionLimit != normalized else { return }

        extensibilityDiagnosticsRetentionLimit = normalized
        if extensibilityDiagnostics.count > normalized {
            extensibilityDiagnostics.removeLast(extensibilityDiagnostics.count - normalized)
        }

        Task { [weak self] in
            guard let self else { return }
            await persistExtensibilityDiagnosticsRetentionLimitIfNeeded()
            await persistExtensibilityDiagnosticsIfNeeded()
        }
    }

    func restoreExtensibilityDiagnosticsIfNeeded() async {
        await restoreExtensibilityDiagnosticsRetentionLimitIfNeeded()

        guard let preferenceRepository else {
            extensibilityDiagnostics = []
            return
        }

        do {
            guard let raw = try await preferenceRepository.getPreference(key: .extensibilityDiagnosticsV1),
                  let data = raw.data(using: .utf8)
            else {
                extensibilityDiagnostics = []
                return
            }

            let decoded = try JSONDecoder().decode([ExtensibilityDiagnosticEvent].self, from: data)
            extensibilityDiagnostics = Array(decoded.prefix(extensibilityDiagnosticsRetentionLimit))
        } catch {
            appendLog(.warning, "Failed to restore extensibility diagnostics cache: \(error.localizedDescription)")
            extensibilityDiagnostics = []
        }
    }

    func persistExtensibilityDiagnosticsIfNeeded() async {
        guard let preferenceRepository else { return }
        do {
            let snapshot = Array(extensibilityDiagnostics.prefix(extensibilityDiagnosticsRetentionLimit))
            let data = try JSONEncoder().encode(snapshot)
            let text = String(data: data, encoding: .utf8) ?? "[]"
            try await preferenceRepository.setPreference(key: .extensibilityDiagnosticsV1, value: text)
        } catch {
            appendLog(.warning, "Failed to persist extensibility diagnostics cache: \(error.localizedDescription)")
        }
    }

    func restoreExtensibilityDiagnosticsRetentionLimitIfNeeded() async {
        guard let preferenceRepository else {
            extensibilityDiagnosticsRetentionLimit = Self.defaultExtensibilityDiagnosticsLimit
            return
        }

        do {
            guard let raw = try await preferenceRepository.getPreference(key: .extensibilityDiagnosticsRetentionLimitV1),
                  let parsed = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                extensibilityDiagnosticsRetentionLimit = Self.defaultExtensibilityDiagnosticsLimit
                return
            }
            extensibilityDiagnosticsRetentionLimit = Self.normalizedDiagnosticsLimit(parsed)
        } catch {
            appendLog(.warning, "Failed to restore extensibility diagnostics retention: \(error.localizedDescription)")
            extensibilityDiagnosticsRetentionLimit = Self.defaultExtensibilityDiagnosticsLimit
        }
    }

    func persistExtensibilityDiagnosticsRetentionLimitIfNeeded() async {
        guard let preferenceRepository else { return }
        do {
            let normalized = Self.normalizedDiagnosticsLimit(extensibilityDiagnosticsRetentionLimit)
            extensibilityDiagnosticsRetentionLimit = normalized
            try await preferenceRepository.setPreference(
                key: .extensibilityDiagnosticsRetentionLimitV1,
                value: String(normalized)
            )
        } catch {
            appendLog(.warning, "Failed to persist extensibility diagnostics retention: \(error.localizedDescription)")
        }
    }

    private static func normalizedDiagnosticsLimit(_ limit: Int) -> Int {
        max(minExtensibilityDiagnosticsLimit, min(maxExtensibilityDiagnosticsLimit, limit))
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

    private static func commandFailurePlaybook(for command: String) -> ExtensibilityDiagnosticPlaybook {
        if command.contains("launchctl") {
            return ExtensibilityDiagnosticPlaybook(
                headline: "Recover background automation state",
                steps: [
                    "Re-enable background automations and confirm launchd permissions in Settings.",
                    "Re-run the automation and verify launchd health in the Mods view.",
                ],
                suggestedCommand: command,
                shortcut: .openAppSettings
            )
        }

        if command.contains("git") || command.contains("npx") {
            return ExtensibilityDiagnosticPlaybook(
                headline: "Validate install source and command access",
                steps: [
                    "Verify repository/package source trust, credentials, and network reachability.",
                    "Run `\(command)` manually to inspect the exact failure details.",
                ],
                suggestedCommand: command,
                shortcut: nil
            )
        }

        return ExtensibilityDiagnosticPlaybook(
            headline: "Retry after validating command prerequisites",
            steps: [
                "Confirm command availability, permissions, and required environment variables.",
                "Re-run the operation after correcting the reported error.",
            ],
            suggestedCommand: command,
            shortcut: nil
        )
    }
}
