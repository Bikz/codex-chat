import CodexChatInfra
import CodexKit
import CodexSkills
import Foundation

public struct CodexChatDoctorCheck: Sendable {
    public enum Status: String, Sendable {
        case ok
        case warning
        case failed
    }

    public let title: String
    public let status: Status
    public let detail: String

    public init(title: String, status: Status, detail: String) {
        self.title = title
        self.status = status
        self.detail = detail
    }
}

public struct CodexChatSmokeSummary: Sendable {
    public let storageRootPath: String
    public let metadataDatabasePath: String
    public let codexExecutablePath: String?

    public init(storageRootPath: String, metadataDatabasePath: String, codexExecutablePath: String?) {
        self.storageRootPath = storageRootPath
        self.metadataDatabasePath = metadataDatabasePath
        self.codexExecutablePath = codexExecutablePath
    }
}

public struct CodexChatReproSummary: Sendable {
    public let fixtureName: String
    public let transcriptLength: Int
    public let actionCount: Int
    public let finalStatus: String

    public init(fixtureName: String, transcriptLength: Int, actionCount: Int, finalStatus: String) {
        self.fixtureName = fixtureName
        self.transcriptLength = transcriptLength
        self.actionCount = actionCount
        self.finalStatus = finalStatus
    }
}

public enum CodexChatBootstrap {
    @MainActor
    static func bootstrapModel() -> AppModel {
        let storagePaths = CodexChatStoragePaths.current()

        do {
            let dependencies = try bootstrapDependencies(storagePaths: storagePaths)
            return AppModel(
                repositories: dependencies.repositories,
                runtime: dependencies.runtime,
                bootError: nil,
                skillCatalogService: dependencies.skillCatalogService,
                skillCatalogProvider: dependencies.skillCatalogProvider,
                storagePaths: dependencies.storagePaths
            )
        } catch {
            return AppModel(
                repositories: nil,
                runtime: nil,
                bootError: error.localizedDescription,
                storagePaths: storagePaths
            )
        }
    }

    public static func doctorChecks(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [CodexChatDoctorCheck] {
        let paths = CodexChatStoragePaths.current()
        let codexExecutable = codexExecutablePath(environment: environment, fileManager: fileManager)

        var checks: [CodexChatDoctorCheck] = [
            CodexChatDoctorCheck(
                title: "Storage root",
                status: .ok,
                detail: paths.rootURL.path
            ),
            CodexChatDoctorCheck(
                title: "Metadata database",
                status: fileManager.fileExists(atPath: paths.metadataDatabaseURL.path) ? .ok : .warning,
                detail: paths.metadataDatabaseURL.path
            ),
        ]

        checks.append(
            CodexChatDoctorCheck(
                title: "Codex CLI",
                status: codexExecutable == nil ? .warning : .ok,
                detail: codexExecutable ?? "Not found in PATH (run `brew install codex`)"
            )
        )

        return checks
    }

    public static func runSmokeCheck(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> CodexChatSmokeSummary {
        let paths = CodexChatStoragePaths.current()
        _ = try bootstrapDependencies(storagePaths: paths, environment: environment, fileManager: fileManager)

        return CodexChatSmokeSummary(
            storageRootPath: paths.rootURL.path,
            metadataDatabasePath: paths.metadataDatabaseURL.path,
            codexExecutablePath: codexExecutablePath(environment: environment, fileManager: fileManager)
        )
    }

    public static func runReproFixture(
        named fixtureName: String,
        fixturesRoot: URL,
        fileManager: FileManager = .default
    ) throws -> CodexChatReproSummary {
        let fixtureURL = fixturesRoot
            .appendingPathComponent(fixtureName, isDirectory: false)
            .appendingPathExtension("json")

        guard fileManager.fileExists(atPath: fixtureURL.path) else {
            throw NSError(
                domain: "CodexChatCLI",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Fixture not found: \(fixtureURL.path)"]
            )
        }

        let data = try Data(contentsOf: fixtureURL)
        let fixture = try JSONDecoder().decode(ReproFixture.self, from: data)

        var transcript = ""
        var actions: [String] = []
        var finalStatus = "unknown"

        for event in fixture.events {
            switch event.kind {
            case .delta:
                transcript.append(event.text ?? "")
            case .action:
                actions.append(event.title ?? "untitled-action")
            case .turnCompleted:
                finalStatus = event.status ?? "unknown"
            }
        }

        guard transcript == fixture.expected.transcript else {
            throw NSError(
                domain: "CodexChatCLI",
                code: 422,
                userInfo: [
                    NSLocalizedDescriptionKey: "Transcript mismatch for fixture \(fixture.name)."
                        + " expected=\(fixture.expected.transcript.count) chars"
                        + " actual=\(transcript.count) chars",
                ]
            )
        }

        guard actions.count == fixture.expected.actionCount else {
            throw NSError(
                domain: "CodexChatCLI",
                code: 422,
                userInfo: [
                    NSLocalizedDescriptionKey: "Action count mismatch for fixture \(fixture.name)."
                        + " expected=\(fixture.expected.actionCount) actual=\(actions.count)",
                ]
            )
        }

        guard finalStatus == fixture.expected.finalStatus else {
            throw NSError(
                domain: "CodexChatCLI",
                code: 422,
                userInfo: [
                    NSLocalizedDescriptionKey: "Completion mismatch for fixture \(fixture.name)."
                        + " expected=\(fixture.expected.finalStatus) actual=\(finalStatus)",
                ]
            )
        }

        return CodexChatReproSummary(
            fixtureName: fixture.name,
            transcriptLength: transcript.count,
            actionCount: actions.count,
            finalStatus: finalStatus
        )
    }

    private static func bootstrapDependencies(
        storagePaths: CodexChatStoragePaths,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> BootstrapDependencies {
        try storagePaths.ensureRootStructure(fileManager: fileManager)
        try CodexChatStorageMigrationCoordinator.performInitialMigrationIfNeeded(paths: storagePaths, fileManager: fileManager)
        _ = try? CodexChatStorageMigrationCoordinator.repairManagedCodexHomeSkillSymlinksIfNeeded(
            paths: storagePaths,
            fileManager: fileManager
        )

        let database = try MetadataDatabase(databaseURL: storagePaths.metadataDatabaseURL)
        let repositories = MetadataRepositories(database: database)
        let skillCatalogService = SkillCatalogService(
            codexHomeURL: storagePaths.codexHomeURL,
            agentsHomeURL: storagePaths.agentsHomeURL
        )
        let skillCatalogProvider = RemoteJSONSkillCatalogProvider(
            indexURL: URL(string: "https://skills.sh/index.json")!
        )
        let runtime = CodexRuntime(
            environmentOverrides: [
                "CODEX_HOME": storagePaths.codexHomeURL.path,
                "PATH": environment["PATH"] ?? "",
            ]
        )

        return BootstrapDependencies(
            repositories: repositories,
            runtime: runtime,
            skillCatalogService: skillCatalogService,
            skillCatalogProvider: skillCatalogProvider,
            storagePaths: storagePaths
        )
    }

    private static func codexExecutablePath(
        environment: [String: String],
        fileManager: FileManager
    ) -> String? {
        let configuredPath = environment["PATH"] ?? ""
        let searchPaths = configuredPath
            .split(separator: ":")
            .map(String.init)
        let candidates = searchPaths.map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("codex") }
            + [
                URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
                URL(fileURLWithPath: "/usr/local/bin/codex"),
            ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate.path
        }

        return nil
    }
}

private extension CodexChatBootstrap {
    struct BootstrapDependencies {
        let repositories: MetadataRepositories
        let runtime: CodexRuntime
        let skillCatalogService: SkillCatalogService
        let skillCatalogProvider: any SkillCatalogProvider
        let storagePaths: CodexChatStoragePaths
    }

    struct ReproFixture: Codable {
        struct Event: Codable {
            enum Kind: String, Codable {
                case delta
                case action
                case turnCompleted
            }

            let kind: Kind
            let text: String?
            let title: String?
            let status: String?
        }

        struct Expected: Codable {
            let transcript: String
            let actionCount: Int
            let finalStatus: String
        }

        let name: String
        let events: [Event]
        let expected: Expected
    }
}
