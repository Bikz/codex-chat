import Foundation

public enum SkillScope: String, CaseIterable, Hashable, Sendable, Codable {
    case project
    case global
}

public enum SkillInstallerKind: String, CaseIterable, Hashable, Sendable, Codable {
    case git
    case npx
}

public struct DiscoveredSkill: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let description: String
    public let scope: SkillScope
    public let skillPath: String
    public let skillDefinitionPath: String
    public let hasScripts: Bool
    public let sourceURL: String?
    public let optionalMetadata: [String: String]

    public init(
        name: String,
        description: String,
        scope: SkillScope,
        skillPath: String,
        skillDefinitionPath: String,
        hasScripts: Bool,
        sourceURL: String?,
        optionalMetadata: [String: String]
    ) {
        self.id = skillPath
        self.name = name
        self.description = description
        self.scope = scope
        self.skillPath = skillPath
        self.skillDefinitionPath = skillDefinitionPath
        self.hasScripts = hasScripts
        self.sourceURL = sourceURL
        self.optionalMetadata = optionalMetadata
    }
}

public struct SkillInstallRequest: Hashable, Sendable {
    public let source: String
    public let scope: SkillScope
    public let projectPath: String?
    public let installer: SkillInstallerKind

    public init(source: String, scope: SkillScope, projectPath: String?, installer: SkillInstallerKind) {
        self.source = source
        self.scope = scope
        self.projectPath = projectPath
        self.installer = installer
    }
}

public struct SkillInstallResult: Hashable, Sendable {
    public let installedPath: String
    public let output: String

    public init(installedPath: String, output: String) {
        self.installedPath = installedPath
        self.output = output
    }
}

public struct SkillUpdateResult: Hashable, Sendable {
    public let output: String

    public init(output: String) {
        self.output = output
    }
}

public enum SkillCatalogError: LocalizedError, Sendable {
    case invalidSource(String)
    case projectPathRequired
    case installTargetExists(String)
    case nodeUnavailable
    case nonGitSkill(String)
    case commandFailed(command: String, output: String)

    public var errorDescription: String? {
        switch self {
        case .invalidSource(let source):
            return "Invalid skill source: \(source)"
        case .projectPathRequired:
            return "Project path is required for project-scoped skill installation."
        case .installTargetExists(let path):
            return "Skill destination already exists: \(path)"
        case .nodeUnavailable:
            return "Node/npx is unavailable on PATH for npx installer."
        case .nonGitSkill(let path):
            return "Skill is not a git repository and cannot be updated: \(path)"
        case .commandFailed(let command, let output):
            return "Skill command failed (\(command)): \(output)"
        }
    }
}

public final class SkillCatalogService: @unchecked Sendable {
    public typealias ProcessRunner = @Sendable (_ argv: [String], _ cwd: String?) throws -> String

    private struct ParsedSkillMetadata {
        let name: String
        let description: String
        let optionalMetadata: [String: String]
    }

    private let fileManager: FileManager
    private let codexHomeURL: URL
    private let agentsHomeURL: URL
    private let processRunner: ProcessRunner

    public init(
        fileManager: FileManager = .default,
        codexHomeURL: URL? = nil,
        agentsHomeURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processRunner: @escaping ProcessRunner = SkillCatalogService.defaultProcessRunner
    ) {
        self.fileManager = fileManager
        self.codexHomeURL = codexHomeURL ?? Self.resolveCodexHome(environment: environment)
        self.agentsHomeURL = agentsHomeURL ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".agents")
        self.processRunner = processRunner
    }

    public func discoverSkills(projectPath: String?) throws -> [DiscoveredSkill] {
        let roots = discoveryRoots(projectPath: projectPath)
        var skillsByPath: [String: DiscoveredSkill] = [:]

        for (root, scope) in roots {
            guard directoryExists(root.path) else { continue }

            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            while let entry = enumerator?.nextObject() as? URL {
                guard entry.lastPathComponent == "SKILL.md" else { continue }
                let skillDirectory = entry.deletingLastPathComponent()
                let standardizedPath = skillDirectory.standardizedFileURL.path
                if skillsByPath[standardizedPath] != nil {
                    continue
                }

                let metadata = try parseSkillMetadata(at: entry)
                let hasScripts = directoryExists(skillDirectory.appendingPathComponent("scripts", isDirectory: true).path)
                let sourceURL = try? gitRemoteURL(for: skillDirectory.path)

                let skill = DiscoveredSkill(
                    name: metadata.name,
                    description: metadata.description,
                    scope: scope,
                    skillPath: standardizedPath,
                    skillDefinitionPath: entry.standardizedFileURL.path,
                    hasScripts: hasScripts,
                    sourceURL: sourceURL,
                    optionalMetadata: metadata.optionalMetadata
                )
                skillsByPath[standardizedPath] = skill
            }
        }

        return skillsByPath.values.sorted {
            if $0.scope != $1.scope {
                return $0.scope.rawValue < $1.scope.rawValue
            }
            if $0.name.caseInsensitiveCompare($1.name) != .orderedSame {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.skillPath < $1.skillPath
        }
    }

    public func installSkill(_ request: SkillInstallRequest) throws -> SkillInstallResult {
        let source = request.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            throw SkillCatalogError.invalidSource(request.source)
        }

        let root = try installRoot(scope: request.scope, projectPath: request.projectPath)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        switch request.installer {
        case .git:
            let destinationName = Self.destinationName(from: source)
            let destination = root.appendingPathComponent(destinationName, isDirectory: true)
            if fileManager.fileExists(atPath: destination.path) {
                throw SkillCatalogError.installTargetExists(destination.path)
            }

            let output = try processRunner(
                ["git", "clone", "--depth", "1", source, destination.path],
                nil
            )
            return SkillInstallResult(installedPath: destination.path, output: output)

        case .npx:
            guard isNodeInstallerAvailable() else {
                throw SkillCatalogError.nodeUnavailable
            }
            let output = try processRunner(["npx", "skills", "add", source], root.path)
            return SkillInstallResult(installedPath: root.path, output: output)
        }
    }

    public func updateSkill(at skillPath: String) throws -> SkillUpdateResult {
        let path = URL(fileURLWithPath: skillPath).standardizedFileURL.path
        let gitDirectory = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent(".git", isDirectory: true)
            .path
        guard directoryExists(gitDirectory) else {
            throw SkillCatalogError.nonGitSkill(path)
        }

        let output = try processRunner(["git", "-C", path, "pull", "--ff-only"], nil)
        return SkillUpdateResult(output: output)
    }

    public func isNodeInstallerAvailable() -> Bool {
        (try? processRunner(["npx", "--version"], nil)) != nil
    }

    public func isTrustedSource(_ source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("./") || trimmed.hasPrefix("../") {
            return true
        }

        if trimmed.hasPrefix("git@") {
            let host = trimmed
                .split(separator: "@", maxSplits: 1)
                .last?
                .split(separator: ":", maxSplits: 1)
                .first
                .map(String.init)?
                .lowercased()
            return Self.trustedHosts.contains(host ?? "")
        }

        if let url = URL(string: trimmed), let host = url.host?.lowercased() {
            return Self.trustedHosts.contains(host)
        }

        return false
    }

    private static let trustedHosts: Set<String> = [
        "github.com",
        "gitlab.com",
        "bitbucket.org"
    ]

    private static func resolveCodexHome(environment: [String: String]) -> URL {
        if let codexHome = environment["CODEX_HOME"], !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    private func discoveryRoots(projectPath: String?) -> [(URL, SkillScope)] {
        var roots: [(URL, SkillScope)] = []
        roots.append((codexHomeURL.appendingPathComponent("skills", isDirectory: true), .global))
        roots.append((agentsHomeURL.appendingPathComponent("skills", isDirectory: true), .global))

        if let projectPath {
            let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)
            roots.append((projectURL.appendingPathComponent(".agents/skills", isDirectory: true), .project))
            roots.append((projectURL.appendingPathComponent(".codex/skills", isDirectory: true), .project))
        }

        var seen = Set<String>()
        return roots.filter {
            let key = $0.0.standardizedFileURL.path
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func installRoot(scope: SkillScope, projectPath: String?) throws -> URL {
        switch scope {
        case .global:
            return codexHomeURL.appendingPathComponent("skills", isDirectory: true)
        case .project:
            guard let projectPath else {
                throw SkillCatalogError.projectPathRequired
            }
            return URL(fileURLWithPath: projectPath, isDirectory: true)
                .appendingPathComponent(".agents/skills", isDirectory: true)
        }
    }

    private static func destinationName(from source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = URL(string: trimmed)?.lastPathComponent
            ?? trimmed.split(separator: "/").last.map(String.init)
            ?? "skill-\(UUID().uuidString.prefix(8))"
        let sanitized = base.replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "skill-\(UUID().uuidString.prefix(8))" : sanitized
    }

    private func parseSkillMetadata(at skillFileURL: URL) throws -> ParsedSkillMetadata {
        let content = try String(contentsOf: skillFileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var frontmatter: [String: String] = [:]
        var bodyStartIndex = 0

        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            for index in 1..<lines.count {
                let line = lines[index].trimmingCharacters(in: .whitespaces)
                if line == "---" {
                    bodyStartIndex = index + 1
                    break
                }
                guard !line.isEmpty, let colonIndex = line.firstIndex(of: ":") else { continue }
                let key = line[..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty, !value.isEmpty {
                    frontmatter[key] = value
                }
            }
        }

        let bodyLines = Array(lines.dropFirst(bodyStartIndex))
        let headingName = bodyLines
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("# ") else { return nil }
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            .first

        let description = frontmatter["description"] ?? bodyLines.first(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            if trimmed.hasPrefix("#") { return false }
            if trimmed == "---" { return false }
            if trimmed.hasPrefix("```") { return false }
            return true
        })?.trimmingCharacters(in: .whitespaces) ?? "No description provided."

        let name = frontmatter["name"]
            ?? headingName
            ?? skillFileURL.deletingLastPathComponent().lastPathComponent

        var optionalMetadata = frontmatter
        optionalMetadata.removeValue(forKey: "name")
        optionalMetadata.removeValue(forKey: "description")

        return ParsedSkillMetadata(
            name: name,
            description: description,
            optionalMetadata: optionalMetadata
        )
    }

    private func gitRemoteURL(for skillPath: String) throws -> String {
        let remote = try processRunner(["git", "-C", skillPath, "config", "--get", "remote.origin.url"], nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remote.isEmpty else {
            throw SkillCatalogError.invalidSource(skillPath)
        }
        return remote
    }

    private func directoryExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public static func defaultProcessRunner(_ argv: [String], _ cwd: String?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let merged = ([stdout, stderr].joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            let command = argv.joined(separator: " ")
            throw SkillCatalogError.commandFailed(command: command, output: merged)
        }

        return merged
    }
}
