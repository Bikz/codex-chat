import CodexChatCore
import Foundation

public final class AppleScriptRunAction: ComputerActionProvider {
    private enum Limits {
        static let maxScriptCharacters = 20000
        static let maxArgumentCount = 24
        static let maxArgumentCharacters = 1024
        static let maxTotalArgumentCharacters = 8192
        static let maxTargetHintCharacters = 80
    }

    private enum Keys {
        static let language = "language"
        static let script = "script"
        static let argumentsJSON = "argumentsJson"
        static let targetHint = "targetHint"
    }

    private struct ParsedRequest: Equatable {
        let language: OsaScriptLanguage
        let script: String
        let arguments: [String]
        let targetHint: String?

        var canonicalArgumentsJSON: String {
            Self.encodeArguments(arguments)
        }

        private static func encodeArguments(_ arguments: [String]) -> String {
            guard let data = try? JSONEncoder().encode(arguments),
                  let text = String(data: data, encoding: .utf8)
            else {
                return "[]"
            }
            return text
        }
    }

    private let runner: any OsaScriptCommandRunning

    public init(runner: any OsaScriptCommandRunning = ProcessOsaScriptRunner()) {
        self.runner = runner
    }

    public let actionID = "apple.script.run"
    public let displayName = "Run AppleScript"
    public let safetyLevel: ComputerActionSafetyLevel = .destructive
    public let requiresConfirmation = true

    public func preview(request: ComputerActionRequest) async throws -> ComputerActionPreviewArtifact {
        let parsed = try parseRequest(request)

        let argsSection: String = if parsed.arguments.isEmpty {
            "- _No script arguments_"
        } else {
            parsed.arguments.enumerated().map { index, value in
                "- [\(index + 1)] `\(value)`"
            }.joined(separator: "\n")
        }

        let languageCodeBlock = parsed.language == .jxa ? "javascript" : "applescript"
        let targetHint = parsed.targetHint?.isEmpty == false ? parsed.targetHint! : "none"

        let details = """
        Language: `\(parsed.language.rawValue)`
        Target hint: `\(targetHint)`

        Script arguments:
        \(argsSection)

        Risk warning: **This script can control macOS apps and local data. Run only if you trust this script.**

        Script preview:

        ```\(languageCodeBlock)
        \(parsed.script)
        ```
        """

        let summary = "Ready to run \(parsed.language.rawValue) with \(parsed.arguments.count) argument(s)."

        return ComputerActionPreviewArtifact(
            actionID: actionID,
            runContextID: request.runContextID,
            title: "Script Execution Preview",
            summary: summary,
            detailsMarkdown: details,
            data: [
                Keys.language: parsed.language.rawValue,
                Keys.script: parsed.script,
                Keys.argumentsJSON: parsed.canonicalArgumentsJSON,
                Keys.targetHint: parsed.targetHint ?? "",
            ]
        )
    }

    public func execute(
        request: ComputerActionRequest,
        preview: ComputerActionPreviewArtifact
    ) async throws -> ComputerActionExecutionResult {
        try validate(preview: preview, request: request)

        let previewParsed = try parsePreview(preview)
        let currentRequest = try parseRequest(request)
        guard previewParsed == currentRequest else {
            throw ComputerActionError.invalidArguments(
                "Script request changed after preview. Generate a fresh preview before running."
            )
        }

        do {
            let output = try await runner.run(
                language: previewParsed.language,
                script: previewParsed.script,
                arguments: previewParsed.arguments
            )

            let outputSummary: String
            let details: String
            if output.isEmpty {
                outputSummary = "Script executed successfully."
                details = "Script completed without output."
            } else {
                outputSummary = "Script executed successfully with output."
                details = """
                Script output:

                ```text
                \(output)
                ```
                """
            }

            return ComputerActionExecutionResult(
                actionID: actionID,
                runContextID: request.runContextID,
                summary: outputSummary,
                detailsMarkdown: details,
                metadata: [
                    Keys.language: previewParsed.language.rawValue,
                    Keys.argumentsJSON: previewParsed.canonicalArgumentsJSON,
                    Keys.targetHint: previewParsed.targetHint ?? "",
                ]
            )
        } catch {
            throw normalizeExecutionError(error, targetHint: previewParsed.targetHint)
        }
    }

    private func parseRequest(_ request: ComputerActionRequest) throws -> ParsedRequest {
        let languageRaw = request.arguments[Keys.language]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? OsaScriptLanguage.applescript.rawValue

        guard let language = OsaScriptLanguage(rawValue: languageRaw) else {
            throw ComputerActionError.invalidArguments(
                "`language` must be `applescript` or `jxa`."
            )
        }

        let script = request.arguments[Keys.script] ?? ""
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ComputerActionError.invalidArguments("Provide a non-empty script before running.")
        }
        guard script.count <= Limits.maxScriptCharacters else {
            throw ComputerActionError.invalidArguments(
                "Script is too large (max \(Limits.maxScriptCharacters) characters)."
            )
        }

        let argumentsJSON = request.arguments[Keys.argumentsJSON] ?? "[]"
        let arguments = try parseArgumentsJSON(argumentsJSON)
        guard arguments.count <= Limits.maxArgumentCount else {
            throw ComputerActionError.invalidArguments(
                "Too many script arguments (max \(Limits.maxArgumentCount))."
            )
        }

        let totalArgumentCharacters = arguments.reduce(0) { $0 + $1.count }
        guard totalArgumentCharacters <= Limits.maxTotalArgumentCharacters else {
            throw ComputerActionError.invalidArguments(
                "Script arguments are too large in total (max \(Limits.maxTotalArgumentCharacters) characters)."
            )
        }

        for argument in arguments where argument.count > Limits.maxArgumentCharacters {
            throw ComputerActionError.invalidArguments(
                "Each script argument must be at most \(Limits.maxArgumentCharacters) characters."
            )
        }

        let targetHint = request.arguments[Keys.targetHint]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let targetHint,
           !targetHint.isEmpty,
           targetHint.count > Limits.maxTargetHintCharacters
        {
            throw ComputerActionError.invalidArguments(
                "`targetHint` is too long (max \(Limits.maxTargetHintCharacters) characters)."
            )
        }

        return ParsedRequest(
            language: language,
            script: script,
            arguments: arguments,
            targetHint: targetHint?.isEmpty == true ? nil : targetHint
        )
    }

    private func parsePreview(_ preview: ComputerActionPreviewArtifact) throws -> ParsedRequest {
        guard let languageRaw = preview.data[Keys.language],
              let language = OsaScriptLanguage(rawValue: languageRaw),
              let script = preview.data[Keys.script],
              let argumentsJSON = preview.data[Keys.argumentsJSON]
        else {
            throw ComputerActionError.invalidPreviewArtifact
        }

        let arguments = try parseArgumentsJSON(argumentsJSON)
        let targetHint = preview.data[Keys.targetHint]?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedRequest(
            language: language,
            script: script,
            arguments: arguments,
            targetHint: targetHint?.isEmpty == true ? nil : targetHint
        )
    }

    private func parseArgumentsJSON(_ argumentsJSON: String) throws -> [String] {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = (trimmed.isEmpty ? "[]" : trimmed).data(using: .utf8) else {
            throw ComputerActionError.invalidArguments("`argumentsJson` must be valid UTF-8 JSON.")
        }

        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            throw ComputerActionError.invalidArguments(
                "`argumentsJson` must be a JSON array of strings."
            )
        }
    }

    private func normalizeExecutionError(
        _ error: Error,
        targetHint: String?
    ) -> ComputerActionError {
        if let computerActionError = error as? ComputerActionError {
            switch computerActionError {
            case let .executionFailed(message):
                if Self.looksLikePermissionDenied(message: message) {
                    return .permissionDenied(Self.permissionDeniedMessage(targetHint: targetHint))
                }
                return computerActionError
            case .permissionDenied:
                return computerActionError
            default:
                return computerActionError
            }
        }

        let message = error.localizedDescription
        if Self.looksLikePermissionDenied(message: message) {
            return .permissionDenied(Self.permissionDeniedMessage(targetHint: targetHint))
        }
        return .executionFailed(message)
    }

    private static func looksLikePermissionDenied(message: String) -> Bool {
        let normalized = message.lowercased()
        let indicators = [
            "not authorized",
            "not permitted",
            "permission",
            "privacy",
            "automation",
            "apple events",
            "erraeeventnotpermitted",
            "-1743",
            "-10004",
            "access is denied",
        ]

        return indicators.contains(where: { normalized.contains($0) })
    }

    private static func permissionDeniedMessage(targetHint: String?) -> String {
        guard let targetHint else {
            return "Script execution was blocked by macOS permissions. Enable access in System Settings > Privacy & Security > Automation."
        }

        let normalized = targetHint.lowercased()
        if normalized.contains("calendar") {
            return "Script execution was blocked by Calendar permissions. Enable access in System Settings > Privacy & Security > Calendars."
        }
        if normalized.contains("reminder") {
            return "Script execution was blocked by Reminders permissions. Enable access in System Settings > Privacy & Security > Reminders."
        }

        return "Script execution was blocked by macOS permissions. Enable access in System Settings > Privacy & Security > Automation."
    }
}
