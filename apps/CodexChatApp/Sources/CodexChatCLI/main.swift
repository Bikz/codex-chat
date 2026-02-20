import CodexChatShared
import CodexMods
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
        print("Smoke check passed")
        print("Storage root: \(summary.storageRootPath)")
        print("Metadata database: \(summary.metadataDatabasePath)")
        print("Codex CLI: \(summary.codexExecutablePath ?? "not found")")
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

    private static func runMod(_ command: CodexChatCLIModCommand) throws {
        switch command {
        case let .validate(source):
            let preview = try ModInstallService().preview(source: source)
            print("Mod package is valid.")
            print("source: \(preview.source)")
            print("id: \(preview.packageManifest.id)")
            print("name: \(preview.packageManifest.name)")
            print("version: \(preview.packageManifest.version)")
            print("permissions: \(preview.requestedPermissions.map(\.rawValue).sorted().joined(separator: ", "))")
            if !preview.warnings.isEmpty {
                fputs("warnings:\n", stderr)
                for warning in preview.warnings {
                    fputs("- \(warning)\n", stderr)
                }
            }

        case let .inspectSource(source):
            let preview = try ModInstallService().preview(source: source)
            let payload = ModInspectPayload(preview: preview)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            guard let json = String(data: data, encoding: .utf8) else {
                throw CLIError("Failed to encode inspect-source output")
            }
            print(json)

        case let .initSample(name, outputPath):
            let discovery = UIModDiscoveryService()
            let definitionURL = try discovery.writeSampleMod(to: outputPath, name: name)
            let packageRoot = definitionURL.deletingLastPathComponent().path
            print("Created sample mod package:")
            print(packageRoot)
            print("Validate with:")
            print("CodexChatCLI mod validate --source \"\(packageRoot)\"")
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
          mod init --name <name>            Create a sample mod package.
               [--output <path>]
          mod validate --source <path|url>  Validate a local/GitHub mod source.
          mod inspect-source --source <path|url>
                                            Print structured source metadata as JSON.
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

private struct ModInspectPayload: Encodable {
    struct UI: Encodable {
        let hookCount: Int
        let automationCount: Int
        let hasModsBarSlot: Bool
    }

    let source: String
    let manifestSource: String
    let id: String
    let name: String
    let version: String
    let permissions: [String]
    let requestedPermissions: [String]
    let warnings: [String]
    let compatibility: ModCompatibility?
    let ui: UI

    init(preview: ModInstallPreview) {
        source = preview.source
        manifestSource = preview.manifestSource.rawValue
        id = preview.packageManifest.id
        name = preview.packageManifest.name
        version = preview.packageManifest.version
        permissions = preview.packageManifest.permissions.map(\.rawValue).sorted()
        requestedPermissions = preview.requestedPermissions.map(\.rawValue).sorted()
        warnings = preview.warnings
        compatibility = preview.packageManifest.compatibility
        ui = UI(
            hookCount: preview.definition.hooks.count,
            automationCount: preview.definition.automations.count,
            hasModsBarSlot: preview.definition.uiSlots?.modsBar?.enabled == true
        )
    }
}
