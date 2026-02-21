import CodexMods
import Foundation

public struct CodexChatCLIModInspectUISummary: Codable, Equatable, Sendable {
    public let hookCount: Int
    public let automationCount: Int
    public let hasModsBarSlot: Bool

    public init(hookCount: Int, automationCount: Int, hasModsBarSlot: Bool) {
        self.hookCount = hookCount
        self.automationCount = automationCount
        self.hasModsBarSlot = hasModsBarSlot
    }
}

public struct CodexChatCLIModInspectPayload: Codable, Equatable, Sendable {
    public let source: String
    public let manifestSource: String
    public let id: String
    public let name: String
    public let version: String
    public let permissions: [String]
    public let requestedPermissions: [String]
    public let warnings: [String]
    public let compatibility: ModCompatibility?
    public let ui: CodexChatCLIModInspectUISummary

    public init(preview: ModInstallPreview) {
        source = preview.source
        manifestSource = preview.manifestSource.rawValue
        id = preview.packageManifest.id
        name = preview.packageManifest.name
        version = preview.packageManifest.version
        permissions = preview.packageManifest.permissions.map(\.rawValue).sorted()
        requestedPermissions = preview.requestedPermissions.map(\.rawValue).sorted()
        warnings = preview.warnings
        compatibility = preview.packageManifest.compatibility
        ui = CodexChatCLIModInspectUISummary(
            hookCount: preview.definition.hooks.count,
            automationCount: preview.definition.automations.count,
            hasModsBarSlot: preview.definition.uiSlots?.modsBar?.enabled == true
        )
    }
}

public struct CodexChatCLIModRunResult: Equatable, Sendable {
    public var stdoutLines: [String]
    public var stderrLines: [String]

    public init(stdoutLines: [String], stderrLines: [String] = []) {
        self.stdoutLines = stdoutLines
        self.stderrLines = stderrLines
    }
}

public enum CodexChatCLIModRunner {
    public static func run(
        command: CodexChatCLIModCommand,
        installService: ModInstallService = .init(),
        discoveryService: UIModDiscoveryService = .init()
    ) throws -> CodexChatCLIModRunResult {
        switch command {
        case let .validate(source):
            let preview = try installService.preview(source: source)
            return CodexChatCLIModRunResult(
                stdoutLines: [
                    "Mod package is valid.",
                    "source: \(preview.source)",
                    "id: \(preview.packageManifest.id)",
                    "name: \(preview.packageManifest.name)",
                    "version: \(preview.packageManifest.version)",
                    "permissions: \(preview.requestedPermissions.map(\.rawValue).sorted().joined(separator: ", "))",
                ],
                stderrLines: preview.warnings.isEmpty ? [] : ["warnings:"] + preview.warnings.map { "- \($0)" }
            )

        case let .inspectSource(source):
            let preview = try installService.preview(source: source)
            let payload = CodexChatCLIModInspectPayload(preview: preview)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            guard let json = String(data: data, encoding: .utf8) else {
                throw CodexChatCLIArgumentError("Failed to encode inspect-source output")
            }
            return CodexChatCLIModRunResult(stdoutLines: [json])

        case let .initSample(name, outputPath):
            let definitionURL = try discoveryService.writeSampleMod(to: outputPath, name: name)
            let packageRoot = definitionURL.deletingLastPathComponent().path
            return CodexChatCLIModRunResult(
                stdoutLines: [
                    "Created sample mod package:",
                    packageRoot,
                    "Validate with:",
                    "CodexChatCLI mod validate --source \"\(packageRoot)\"",
                ]
            )
        }
    }
}
