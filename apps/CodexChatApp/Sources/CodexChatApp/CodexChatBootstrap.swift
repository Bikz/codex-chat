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
                storagePaths: dependencies.storagePaths,
                harnessEnvironment: dependencies.harnessEnvironment
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
        let harnessEnvironment = try makeHarnessEnvironment(
            storagePaths: storagePaths,
            environment: environment,
            fileManager: fileManager
        )
        let existingPath = environment["PATH"] ?? ""
        let runtimePath = prependPathEntry(
            URL(fileURLWithPath: harnessEnvironment.wrapperPath, isDirectory: false)
                .deletingLastPathComponent()
                .path,
            toPath: existingPath
        )
        let runtime = CodexRuntime(
            environmentOverrides: [
                "CODEX_HOME": storagePaths.codexHomeURL.path,
                "CODEXCHAT_HARNESS_SOCKET": harnessEnvironment.socketPath,
                "CODEXCHAT_HARNESS_SESSION_TOKEN": harnessEnvironment.sessionToken,
                "CODEXCHAT_HARNESS_WRAPPER_PATH": harnessEnvironment.wrapperPath,
                "PATH": runtimePath,
            ]
        )

        return BootstrapDependencies(
            repositories: repositories,
            runtime: runtime,
            skillCatalogService: skillCatalogService,
            skillCatalogProvider: skillCatalogProvider,
            storagePaths: storagePaths,
            harnessEnvironment: harnessEnvironment
        )
    }

    private static func makeHarnessEnvironment(
        storagePaths: CodexChatStoragePaths,
        environment: [String: String],
        fileManager: FileManager
    ) throws -> ComputerActionHarnessEnvironment {
        let harnessRootURL = storagePaths.systemURL
            .appendingPathComponent("computer-action-harness", isDirectory: true)
        try fileManager.createDirectory(at: harnessRootURL, withIntermediateDirectories: true)

        let wrapperPath = try ensureHarnessWrapperCommand(
            storagePaths: storagePaths,
            environment: environment,
            fileManager: fileManager
        )
        return ComputerActionHarnessEnvironment(
            socketPath: harnessRootURL.appendingPathComponent("harness.sock", isDirectory: false).path,
            sessionToken: UUID().uuidString.lowercased(),
            wrapperPath: wrapperPath
        )
    }

    private static func ensureHarnessWrapperCommand(
        storagePaths: CodexChatStoragePaths,
        environment: [String: String],
        fileManager: FileManager
    ) throws -> String {
        let wrapperDirectory = storagePaths.systemURL
            .appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: wrapperDirectory, withIntermediateDirectories: true)

        let wrapperURL = wrapperDirectory.appendingPathComponent("codexchat-action", isDirectory: false)
        let script = harnessWrapperScriptContent(environment: environment)

        if let existing = try? String(contentsOf: wrapperURL, encoding: .utf8),
           existing == script
        {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapperURL.path)
            return wrapperURL.path
        }

        try script.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapperURL.path)
        return wrapperURL.path
    }

    private static func harnessWrapperScriptContent(environment: [String: String]) -> String {
        let pythonPath = resolvePythonPath(environment: environment)
        return """
        #!/bin/sh
        exec "\(pythonPath)" - <<'PYTHON' "$@"
        import argparse
        import json
        import os
        import socket
        import sys
        import uuid


        def emit(payload):
            sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\\n")


        parser = argparse.ArgumentParser(prog="codexchat-action")
        subparsers = parser.add_subparsers(dest="command")
        invoke = subparsers.add_parser("invoke")
        invoke.add_argument("--run-token", required=True)
        invoke.add_argument("--action-id", required=True)
        invoke.add_argument("--arguments-json", default="{}")
        invoke.add_argument("--request-id")

        args = parser.parse_args()

        if args.command != "invoke":
            emit(
                {
                    "requestID": "",
                    "status": "invalid",
                    "summary": "Unsupported command.",
                    "errorCode": "unsupported_command",
                    "errorMessage": "Use: codexchat-action invoke ...",
                }
            )
            sys.exit(2)

        socket_path = os.getenv("CODEXCHAT_HARNESS_SOCKET", "").strip()
        session_token = os.getenv("CODEXCHAT_HARNESS_SESSION_TOKEN", "").strip()
        if not socket_path or not session_token:
            emit(
                {
                    "requestID": args.request_id or "",
                    "status": "unauthorized",
                    "summary": "Harness session is not configured.",
                    "errorCode": "missing_harness_environment",
                    "errorMessage": "Missing CODEXCHAT_HARNESS_SOCKET or CODEXCHAT_HARNESS_SESSION_TOKEN.",
                }
            )
            sys.exit(3)

        try:
            parsed_arguments = json.loads(args.arguments_json)
            if not isinstance(parsed_arguments, dict):
                raise ValueError("arguments json must decode to an object")
        except Exception as exc:
            emit(
                {
                    "requestID": args.request_id or "",
                    "status": "invalid",
                    "summary": "Invalid arguments json.",
                    "errorCode": "invalid_arguments_json",
                    "errorMessage": str(exc),
                }
            )
            sys.exit(2)

        request_id = args.request_id or str(uuid.uuid4()).lower()
        request = {
            "protocolVersion": 1,
            "requestID": request_id,
            "sessionToken": session_token,
            "runToken": args.run_token,
            "actionID": args.action_id,
            "argumentsJson": json.dumps(parsed_arguments, separators=(",", ":")),
        }

        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.connect(socket_path)
                client.sendall((json.dumps(request, separators=(",", ":")) + "\\n").encode("utf-8"))
                data = b""
                while not data.endswith(b"\\n"):
                    chunk = client.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                    if len(data) > 131072:
                        break
        except Exception as exc:
            emit(
                {
                    "requestID": request_id,
                    "status": "invalid",
                    "summary": "Failed to invoke harness endpoint.",
                    "errorCode": "transport_error",
                    "errorMessage": str(exc),
                }
            )
            sys.exit(4)

        if not data:
            emit(
                {
                    "requestID": request_id,
                    "status": "invalid",
                    "summary": "Harness returned no response.",
                    "errorCode": "empty_response",
                    "errorMessage": "No response received from harness socket.",
                }
            )
            sys.exit(4)

        line = data.splitlines()[0] if b"\\n" in data else data
        try:
            response = json.loads(line.decode("utf-8"))
        except Exception as exc:
            emit(
                {
                    "requestID": request_id,
                    "status": "invalid",
                    "summary": "Harness returned invalid JSON.",
                    "errorCode": "invalid_response_json",
                    "errorMessage": str(exc),
                }
            )
            sys.exit(4)

        emit(response)
        status = response.get("status")
        if status in {"executed", "queued_for_approval"}:
            sys.exit(0)
        sys.exit(1)
        PYTHON
        """
    }

    private static func resolvePythonPath(environment: [String: String]) -> String {
        let configuredPath = environment["PATH"] ?? ""
        for pathEntry in configuredPath.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: pathEntry, isDirectory: true)
                .appendingPathComponent("python3", isDirectory: false)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return "/usr/bin/python3"
    }

    private static func prependPathEntry(_ entry: String, toPath existingPath: String) -> String {
        guard !entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return existingPath
        }

        if existingPath.isEmpty {
            return entry
        }

        let currentEntries = existingPath.split(separator: ":").map(String.init)
        if currentEntries.contains(entry) {
            return existingPath
        }
        return "\(entry):\(existingPath)"
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
        let harnessEnvironment: ComputerActionHarnessEnvironment
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
