import Foundation

enum CodexRoleProfileBuilderError: LocalizedError {
    case missingProfileName
    case missingRoleName
    case missingModel

    var errorDescription: String? {
        switch self {
        case .missingProfileName:
            "Enter a profile name before applying the builder."
        case .missingRoleName:
            "Enter an agent role name before applying the builder."
        case .missingModel:
            "Enter a model for the profile/role template."
        }
    }
}

struct CodexRoleProfileBuilderInput: Hashable, Sendable {
    var profileName = ""
    var profileModel = "gpt-5.3-codex"
    var profileReasoningEffort = "high"
    var profileReasoningSummary = "detailed"
    var profileVerbosity = "high"
    var profilePersonality = "pragmatic"

    var roleName = ""
    var roleDescription = ""
    var roleConfigFilename = ""
    var roleDeveloperInstructions = ""
}

struct CodexRoleProfileBuilderOutput: Hashable, Sendable {
    let updatedRoot: CodexConfigValue
    let roleConfigPath: String
    let roleConfigContents: String
    let normalizedProfileName: String
    let normalizedRoleName: String
}

enum CodexRoleProfileBuilder {
    static func build(
        input: CodexRoleProfileBuilderInput,
        root: CodexConfigValue,
        codexHomeURL: URL
    ) throws -> CodexRoleProfileBuilderOutput {
        let profileName = normalizedKey(input.profileName)
        guard !profileName.isEmpty else {
            throw CodexRoleProfileBuilderError.missingProfileName
        }

        let roleName = normalizedKey(input.roleName)
        guard !roleName.isEmpty else {
            throw CodexRoleProfileBuilderError.missingRoleName
        }

        let model = input.profileModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw CodexRoleProfileBuilderError.missingModel
        }

        let roleFilename = normalizedRoleFilename(
            input.roleConfigFilename,
            roleName: roleName
        )

        let roleConfigURL = codexHomeURL
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(roleFilename, isDirectory: false)

        let profileObject = buildProfileObject(input: input, model: model)
        let roleDescription = input.roleDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var updatedRoot = root
        updatedRoot.setValue(
            .object(profileObject),
            at: [.key("profiles"), .key(profileName)]
        )
        updatedRoot.setValue(
            .string(roleDescription.isEmpty ? "Describe when this role should run." : roleDescription),
            at: [.key("agents"), .key(roleName), .key("description")]
        )
        updatedRoot.setValue(
            .string(roleConfigURL.path),
            at: [.key("agents"), .key(roleName), .key("config_file")]
        )

        return CodexRoleProfileBuilderOutput(
            updatedRoot: updatedRoot,
            roleConfigPath: roleConfigURL.path,
            roleConfigContents: roleTemplateContents(input: input, model: model),
            normalizedProfileName: profileName,
            normalizedRoleName: roleName
        )
    }

    static func writeRoleTemplate(
        contents: String,
        to path: String,
        fileManager: FileManager = .default
    ) throws {
        let fileURL = URL(fileURLWithPath: path, isDirectory: false)
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func buildProfileObject(
        input: CodexRoleProfileBuilderInput,
        model: String
    ) -> [String: CodexConfigValue] {
        var object: [String: CodexConfigValue] = [
            "model": .string(model),
        ]

        setOptionalString(input.profileReasoningEffort, key: "model_reasoning_effort", in: &object)
        setOptionalString(input.profileReasoningSummary, key: "model_reasoning_summary", in: &object)
        setOptionalString(input.profileVerbosity, key: "model_verbosity", in: &object)
        setOptionalString(input.profilePersonality, key: "personality", in: &object)

        return object
    }

    private static func roleTemplateContents(
        input: CodexRoleProfileBuilderInput,
        model: String
    ) -> String {
        let instructions = input.roleDeveloperInstructions
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = [
            "model = \"\(model)\"",
        ]

        if let reasoning = normalizedOptionalValue(input.profileReasoningEffort) {
            lines.append("model_reasoning_effort = \"\(reasoning)\"")
        }
        if let summary = normalizedOptionalValue(input.profileReasoningSummary) {
            lines.append("model_reasoning_summary = \"\(summary)\"")
        }
        if let verbosity = normalizedOptionalValue(input.profileVerbosity) {
            lines.append("model_verbosity = \"\(verbosity)\"")
        }
        if let personality = normalizedOptionalValue(input.profilePersonality) {
            lines.append("personality = \"\(personality)\"")
        }

        lines.append("")
        lines.append("developer_instructions = \"\"\"")
        if instructions.isEmpty {
            lines.append("Define role instructions here. Keep them concise and task-specific.")
        } else {
            lines.append(contentsOf: instructions
                .replacingOccurrences(of: "\"\"\"", with: "\\\"\\\"\\\"")
                .components(separatedBy: "\n"))
        }
        lines.append("\"\"\"")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func setOptionalString(
        _ value: String,
        key: String,
        in object: inout [String: CodexConfigValue]
    ) {
        guard let normalized = normalizedOptionalValue(value) else {
            return
        }
        object[key] = .string(normalized)
    }

    private static func normalizedOptionalValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedKey(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else {
            return ""
        }

        let mapped = lowered.map { character -> Character in
            if character.isLetter || character.isNumber || character == "_" || character == "-" {
                return character
            }
            return "_"
        }

        return String(mapped)
            .replacingOccurrences(of: "__", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func normalizedRoleFilename(_ value: String, roleName: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "\(roleName).toml" : trimmed

        let sanitized = base
            .replacingOccurrences(of: "..", with: "")
            .split(separator: "/")
            .last
            .map(String.init) ?? "\(roleName).toml"

        if sanitized.hasSuffix(".toml") {
            return sanitized
        }

        return "\(sanitized).toml"
    }
}
