import CodexProcess
import Foundation

public enum SkillScope: String, CaseIterable, Hashable, Sendable, Codable {
    case project
    case global
}

public enum SkillInstallerKind: String, CaseIterable, Hashable, Sendable, Codable {
    case git
    case npx
}

public enum SkillUpdateCapabilityKind: String, CaseIterable, Hashable, Sendable, Codable {
    case gitUpdate
    case reinstall
    case unavailable
}

public struct SkillInstallMetadata: Hashable, Sendable, Codable {
    public let source: String
    public let installer: SkillInstallerKind
    public let pinnedRef: String?
    public let installedAt: Date?
    public let updatedAt: Date?

    public init(
        source: String,
        installer: SkillInstallerKind,
        pinnedRef: String? = nil,
        installedAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.source = source
        self.installer = installer
        self.pinnedRef = pinnedRef
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }
}

public struct SkillUpdateCapabilityResult: Hashable, Sendable {
    public let kind: SkillUpdateCapabilityKind
    public let source: String?
    public let installer: SkillInstallerKind?

    public init(kind: SkillUpdateCapabilityKind, source: String?, installer: SkillInstallerKind?) {
        self.kind = kind
        self.source = source
        self.installer = installer
    }
}

public struct CatalogSkillListing: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String?
    public let repositoryURL: String?
    public let installSource: String?
    public let rank: Double?

    public init(
        id: String,
        name: String,
        summary: String? = nil,
        repositoryURL: String? = nil,
        installSource: String? = nil,
        rank: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.repositoryURL = repositoryURL
        self.installSource = installSource
        self.rank = rank
    }
}

public protocol SkillCatalogProvider: Sendable {
    func listAvailableSkills() async throws -> [CatalogSkillListing]
}

public struct EmptySkillCatalogProvider: SkillCatalogProvider {
    public init() {}

    public func listAvailableSkills() async throws -> [CatalogSkillListing] {
        []
    }
}

public struct RemoteJSONSkillCatalogProvider: SkillCatalogProvider {
    public static let defaultIndexURL = URL(string: "https://skills.sh/api/skills/all-time/0")!

    public let indexURL: URL
    public let urlSession: URLSession

    private struct WrappedIndex: Codable {
        var skills: [CatalogSkillListing]
    }

    private struct SkillsAPIPage: Codable {
        var skills: [SkillsAPIEntry]
    }

    private struct SkillsAPIEntry: Codable {
        var source: String
        var skillId: String
        var name: String
        var installs: Double?
    }

    public init(indexURL: URL = RemoteJSONSkillCatalogProvider.defaultIndexURL, urlSession: URLSession = .shared) {
        self.indexURL = indexURL
        self.urlSession = urlSession
    }

    public func listAvailableSkills() async throws -> [CatalogSkillListing] {
        let (data, response) = try await urlSession.data(from: indexURL)
        if let response = response as? HTTPURLResponse,
           !(200 ... 299).contains(response.statusCode)
        {
            throw NSError(
                domain: "CodexSkills.RemoteCatalog",
                code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Catalog request failed with status \(response.statusCode)."]
            )
        }

        let decoder = JSONDecoder()
        let listings: [CatalogSkillListing]
        do {
            listings = try decoder.decode([CatalogSkillListing].self, from: data)
        } catch {
            do {
                listings = try decoder.decode(WrappedIndex.self, from: data).skills
            } catch {
                do {
                    let page = try decoder.decode(SkillsAPIPage.self, from: data)
                    listings = page.skills.map(Self.catalogListing(from:))
                } catch {
                    throw NSError(
                        domain: "CodexSkills.RemoteCatalog",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Catalog payload could not be decoded.",
                            NSUnderlyingErrorKey: error,
                        ]
                    )
                }
            }
        }

        return listings.sorted {
            let lhs = $0.rank ?? -Double.greatestFiniteMagnitude
            let rhs = $1.rank ?? -Double.greatestFiniteMagnitude
            if lhs == rhs {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return lhs > rhs
        }
    }

    private static func catalogListing(from entry: SkillsAPIEntry) -> CatalogSkillListing {
        let source = entry.source.trimmingCharacters(in: .whitespacesAndNewlines)
        let skillID = entry.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackID = entry.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let listingID = [source.lowercased(), skillID.lowercased()]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        let normalizedID = listingID.isEmpty ? fallbackID : listingID
        let repositoryURL = githubRepositoryURL(from: source)
        let installSource = repositoryURL.map { "\($0).git" }
        let summary = source.isEmpty ? nil : "From \(source)"

        return CatalogSkillListing(
            id: normalizedID,
            name: entry.name,
            summary: summary,
            repositoryURL: repositoryURL,
            installSource: installSource,
            rank: entry.installs
        )
    }

    private static func githubRepositoryURL(from source: String) -> String? {
        let parts = source.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return nil
        }

        let owner = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repo.isEmpty else {
            return nil
        }

        return "https://github.com/\(owner)/\(repo)"
    }
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
    public let installMetadata: SkillInstallMetadata?
    public let isGitRepository: Bool

    public init(
        name: String,
        description: String,
        scope: SkillScope,
        skillPath: String,
        skillDefinitionPath: String,
        hasScripts: Bool,
        sourceURL: String?,
        optionalMetadata: [String: String],
        installMetadata: SkillInstallMetadata? = nil,
        isGitRepository: Bool = false
    ) {
        id = skillPath
        self.name = name
        self.description = description
        self.scope = scope
        self.skillPath = skillPath
        self.skillDefinitionPath = skillDefinitionPath
        self.hasScripts = hasScripts
        self.sourceURL = sourceURL
        self.optionalMetadata = optionalMetadata
        self.installMetadata = installMetadata
        self.isGitRepository = isGitRepository
    }
}

public struct SkillInstallRequest: Hashable, Sendable {
    public let source: String
    public let scope: SkillScope
    public let projectPath: String?
    public let installer: SkillInstallerKind
    public let pinnedRef: String?
    public let allowUntrustedSource: Bool

    public init(
        source: String,
        scope: SkillScope,
        projectPath: String?,
        installer: SkillInstallerKind,
        pinnedRef: String? = nil,
        allowUntrustedSource: Bool = false
    ) {
        self.source = source
        self.scope = scope
        self.projectPath = projectPath
        self.installer = installer
        self.pinnedRef = pinnedRef
        self.allowUntrustedSource = allowUntrustedSource
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
    case installPathUnresolved(String)
    case nodeUnavailable
    case nonGitSkill(String)
    case installMetadataMissing(String)
    case reinstallSourceMissing(String)
    case untrustedSourceRequiresConfirmation(String)
    case commandFailed(command: String, output: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidSource(source):
            "Invalid skill source: \(source)"
        case .projectPathRequired:
            "Project path is required for project-scoped skill installation."
        case let .installTargetExists(path):
            "Skill destination already exists: \(path)"
        case let .installPathUnresolved(path):
            "Skill install path could not be determined under \(path)."
        case .nodeUnavailable:
            "Node/npx is unavailable on PATH for npx installer."
        case let .nonGitSkill(path):
            "Skill is not a git repository and cannot be updated: \(path)"
        case let .installMetadataMissing(path):
            "Skill install metadata is missing: \(path)"
        case let .reinstallSourceMissing(path):
            "Skill reinstall source is unavailable: \(path)"
        case let .untrustedSourceRequiresConfirmation(source):
            "Untrusted skill source requires explicit confirmation: \(source)"
        case let .commandFailed(command, output):
            "Skill command failed (\(command)): \(output)"
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

    private struct InstallMetadataPayload: Codable {
        let source: String
        let installer: SkillInstallerKind
        let pinnedRef: String?
        let installedAt: Date
        let updatedAt: Date?
    }

    private struct SourceReference {
        let source: String
        let pinnedRef: String?
    }

    private struct DiscoveryCacheKey: Hashable {
        let roots: [String]
    }

    private struct DiscoveryRootSignature: Hashable {
        let rootPath: String
        let skillFileCount: Int
        let latestSkillFileMTime: TimeInterval
    }

    private struct DiscoveryCacheEntry {
        let signatures: [DiscoveryRootSignature]
        let skills: [DiscoveredSkill]
    }

    private let fileManager: FileManager
    private let codexHomeURL: URL
    private let agentsHomeURL: URL
    private let processRunner: ProcessRunner
    private let discoveryCacheLock = NSLock()
    private var discoveryCache: [DiscoveryCacheKey: DiscoveryCacheEntry] = [:]

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
        let cacheKey = DiscoveryCacheKey(
            roots: roots.map { "\($0.0.standardizedFileURL.path)#\($0.1.rawValue)" }
        )
        let signatures = discoverySignatures(for: roots)
        if let cached = cachedDiscovery(for: cacheKey, signatures: signatures) {
            return cached
        }

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
                let installMetadata = try? readInstallMetadata(at: skillDirectory)
                let hasScripts = directoryExists(skillDirectory.appendingPathComponent("scripts", isDirectory: true).path)
                let isGitRepository = directoryExists(skillDirectory.appendingPathComponent(".git", isDirectory: true).path)
                let sourceURL = installMetadata?.source
                    ?? metadata.optionalMetadata["source"]
                    ?? metadata.optionalMetadata["repository"]

                let skill = DiscoveredSkill(
                    name: metadata.name,
                    description: metadata.description,
                    scope: scope,
                    skillPath: standardizedPath,
                    skillDefinitionPath: entry.standardizedFileURL.path,
                    hasScripts: hasScripts,
                    sourceURL: sourceURL,
                    optionalMetadata: metadata.optionalMetadata,
                    installMetadata: installMetadata,
                    isGitRepository: isGitRepository
                )
                skillsByPath[standardizedPath] = skill
            }
        }

        let sortedSkills = skillsByPath.values.sorted {
            if $0.scope != $1.scope {
                return $0.scope.rawValue < $1.scope.rawValue
            }
            if $0.name.caseInsensitiveCompare($1.name) != .orderedSame {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.skillPath < $1.skillPath
        }
        storeDiscovery(sortedSkills, for: cacheKey, signatures: signatures)
        return sortedSkills
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
            let parsed = Self.parseSourceReference(source: source, explicitPinnedRef: request.pinnedRef)
            guard isTrustedSource(parsed.source) || request.allowUntrustedSource else {
                throw SkillCatalogError.untrustedSourceRequiresConfirmation(parsed.source)
            }

            let destinationName = Self.destinationName(from: parsed.source)
            let destination = root.appendingPathComponent(destinationName, isDirectory: true)
            if fileManager.fileExists(atPath: destination.path) {
                throw SkillCatalogError.installTargetExists(destination.path)
            }

            let output = try processRunner(
                ["git", "clone", "--depth", "1", parsed.source, destination.path],
                nil
            )
            let checkoutOutput = try checkoutPinnedRefIfNeeded(
                at: destination.path,
                pinnedRef: parsed.pinnedRef
            )
            let combinedOutput = [output, checkoutOutput]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            if directoryExists(destination.path) {
                try? writeInstallMetadata(
                    at: destination,
                    metadata: SkillInstallMetadata(
                        source: parsed.source,
                        installer: .git,
                        pinnedRef: parsed.pinnedRef,
                        installedAt: Date(),
                        updatedAt: Date()
                    )
                )
            }
            invalidateDiscoveryCache()
            return SkillInstallResult(installedPath: destination.path, output: combinedOutput)

        case .npx:
            guard isTrustedSource(source) || request.allowUntrustedSource else {
                throw SkillCatalogError.untrustedSourceRequiresConfirmation(source)
            }
            guard isNodeInstallerAvailable() else {
                throw SkillCatalogError.nodeUnavailable
            }
            let before = directoryChildren(in: root)
            let output = try processRunner(["npx", "skills", "add", source], root.path)
            let after = directoryChildren(in: root)
            guard let installedPath = inferInstalledPath(
                source: source,
                root: root,
                beforeDirectories: before,
                afterDirectories: after
            ) else {
                throw SkillCatalogError.installPathUnresolved(root.path)
            }
            try? writeInstallMetadata(
                at: URL(fileURLWithPath: installedPath, isDirectory: true),
                metadata: SkillInstallMetadata(
                    source: source,
                    installer: .npx,
                    pinnedRef: nil,
                    installedAt: Date(),
                    updatedAt: Date()
                )
            )
            invalidateDiscoveryCache()
            return SkillInstallResult(installedPath: installedPath, output: output)
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

        let metadata = try? readInstallMetadata(at: URL(fileURLWithPath: path, isDirectory: true))
        let output: String
        if let pinnedRef = metadata?.pinnedRef?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pinnedRef.isEmpty
        {
            let fetch = try processRunner(["git", "-C", path, "fetch", "--depth", "1", "origin", pinnedRef], nil)
            let checkout = try processRunner(["git", "-C", path, "checkout", "--detach", "FETCH_HEAD"], nil)
            output = [fetch, checkout]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
        } else {
            output = try processRunner(["git", "-C", path, "pull", "--ff-only"], nil)
        }

        if var metadata {
            metadata = SkillInstallMetadata(
                source: metadata.source,
                installer: metadata.installer,
                pinnedRef: metadata.pinnedRef,
                installedAt: metadata.installedAt,
                updatedAt: Date()
            )
            try? writeInstallMetadata(at: URL(fileURLWithPath: path, isDirectory: true), metadata: metadata)
        }
        invalidateDiscoveryCache()
        return SkillUpdateResult(output: output)
    }

    public func reinstallSkill(_ skill: DiscoveredSkill) throws -> SkillInstallResult {
        let capability = updateCapability(for: skill)
        guard capability.kind == .reinstall, let source = capability.source, let installer = capability.installer else {
            throw SkillCatalogError.reinstallSourceMissing(skill.skillPath)
        }

        let skillURL = URL(fileURLWithPath: skill.skillPath, isDirectory: true)
        let parent = skillURL.deletingLastPathComponent()

        switch installer {
        case .git:
            let parsed = Self.parseSourceReference(source: source, explicitPinnedRef: skill.installMetadata?.pinnedRef)
            let stagingURL = try createStagingDirectory(in: parent)
            defer { try? fileManager.removeItem(at: stagingURL) }

            let output = try processRunner(["git", "clone", "--depth", "1", parsed.source, stagingURL.path], nil)
            let checkoutOutput = try checkoutPinnedRefIfNeeded(at: stagingURL.path, pinnedRef: parsed.pinnedRef)
            let combinedOutput = [output, checkoutOutput]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            try writeInstallMetadata(
                at: stagingURL,
                metadata: SkillInstallMetadata(
                    source: parsed.source,
                    installer: .git,
                    pinnedRef: parsed.pinnedRef,
                    installedAt: Date(),
                    updatedAt: Date()
                )
            )
            try replaceDirectoryAtomically(existingURL: skillURL, replacementURL: stagingURL)
            invalidateDiscoveryCache()
            return SkillInstallResult(installedPath: skillURL.path, output: combinedOutput)

        case .npx:
            guard isNodeInstallerAvailable() else {
                throw SkillCatalogError.nodeUnavailable
            }

            let stagingRootURL = try createStagingDirectory(in: parent)
            defer { try? fileManager.removeItem(at: stagingRootURL) }

            let before = directoryChildren(in: stagingRootURL)
            let output = try processRunner(["npx", "skills", "add", source], stagingRootURL.path)
            let after = directoryChildren(in: stagingRootURL)
            guard let installedPath = inferInstalledPath(
                source: source,
                root: stagingRootURL,
                beforeDirectories: before,
                afterDirectories: after
            ) else {
                throw SkillCatalogError.installPathUnresolved(stagingRootURL.path)
            }

            let installedURL = URL(fileURLWithPath: installedPath, isDirectory: true)
            try writeInstallMetadata(
                at: installedURL,
                metadata: SkillInstallMetadata(
                    source: source,
                    installer: .npx,
                    pinnedRef: nil,
                    installedAt: Date(),
                    updatedAt: Date()
                )
            )
            try replaceDirectoryAtomically(existingURL: skillURL, replacementURL: installedURL)
            invalidateDiscoveryCache()

            return SkillInstallResult(installedPath: skillURL.path, output: output)
        }
    }

    public func updateCapability(for skill: DiscoveredSkill) -> SkillUpdateCapabilityResult {
        if skill.isGitRepository {
            return SkillUpdateCapabilityResult(kind: .gitUpdate, source: skill.sourceURL, installer: .git)
        }

        if let metadata = skill.installMetadata,
           !metadata.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return SkillUpdateCapabilityResult(kind: .reinstall, source: metadata.source, installer: metadata.installer)
        }

        if let sourceURL = skill.sourceURL,
           !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return SkillUpdateCapabilityResult(kind: .reinstall, source: sourceURL, installer: .git)
        }

        return SkillUpdateCapabilityResult(kind: .unavailable, source: nil, installer: nil)
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
        "bitbucket.org",
    ]

    private static func resolveCodexHome(environment: [String: String]) -> URL {
        if let codexHome = environment["CODEX_HOME"], !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    private func cachedDiscovery(
        for key: DiscoveryCacheKey,
        signatures: [DiscoveryRootSignature]
    ) -> [DiscoveredSkill]? {
        discoveryCacheLock.lock()
        defer { discoveryCacheLock.unlock() }
        guard let entry = discoveryCache[key], entry.signatures == signatures else {
            return nil
        }
        return entry.skills
    }

    private func storeDiscovery(
        _ skills: [DiscoveredSkill],
        for key: DiscoveryCacheKey,
        signatures: [DiscoveryRootSignature]
    ) {
        discoveryCacheLock.lock()
        discoveryCache[key] = DiscoveryCacheEntry(signatures: signatures, skills: skills)
        discoveryCacheLock.unlock()
    }

    private func invalidateDiscoveryCache() {
        discoveryCacheLock.lock()
        discoveryCache = [:]
        discoveryCacheLock.unlock()
    }

    private func discoverySignatures(
        for roots: [(URL, SkillScope)]
    ) -> [DiscoveryRootSignature] {
        roots.map { root, _ in
            guard directoryExists(root.path) else {
                return DiscoveryRootSignature(rootPath: root.standardizedFileURL.path, skillFileCount: 0, latestSkillFileMTime: 0)
            }

            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            var fileCount = 0
            var latest = TimeInterval(0)
            while let entry = enumerator?.nextObject() as? URL {
                guard entry.lastPathComponent == "SKILL.md" else { continue }
                fileCount += 1
                let mTime = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
                    .timeIntervalSince1970 ?? 0
                if mTime > latest {
                    latest = mTime
                }
            }

            return DiscoveryRootSignature(
                rootPath: root.standardizedFileURL.path,
                skillFileCount: fileCount,
                latestSkillFileMTime: latest
            )
        }
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
            ?? ""

        let withoutSuffix = base
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = withoutSuffix.unicodeScalars.map { scalar -> Character in
            if allowed.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }

        let collapsed = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))

        if collapsed.isEmpty || collapsed == "." || collapsed == ".." {
            return "skill-\(UUID().uuidString.prefix(8))"
        }

        return collapsed
    }

    private func parseSkillMetadata(at skillFileURL: URL) throws -> ParsedSkillMetadata {
        let content = try String(contentsOf: skillFileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var frontmatter: [String: String] = [:]
        var bodyStartIndex = 0

        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            for index in 1 ..< lines.count {
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

    private func directoryChildren(in root: URL) -> Set<String> {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var names: Set<String> = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true else {
                continue
            }
            names.insert(url.lastPathComponent)
        }
        return names
    }

    private func createStagingDirectory(in parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(".codexchat-skill-stage-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func replaceDirectoryAtomically(existingURL: URL, replacementURL: URL) throws {
        let normalizedExistingPath = existingURL.standardizedFileURL.path
        let normalizedReplacementPath = replacementURL.standardizedFileURL.path
        guard normalizedExistingPath != normalizedReplacementPath else { return }

        let parentURL = existingURL.deletingLastPathComponent()
        let backupURL = parentURL.appendingPathComponent(".\(existingURL.lastPathComponent).backup-\(UUID().uuidString)", isDirectory: true)
        let hasExisting = fileManager.fileExists(atPath: existingURL.path)
        if hasExisting {
            try fileManager.moveItem(at: existingURL, to: backupURL)
        }

        do {
            try fileManager.moveItem(at: replacementURL, to: existingURL)
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
        } catch {
            if fileManager.fileExists(atPath: existingURL.path) {
                try? fileManager.removeItem(at: existingURL)
            }
            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: existingURL)
            }
            throw error
        }
    }

    private func inferInstalledPath(
        source: String,
        root: URL,
        beforeDirectories: Set<String>,
        afterDirectories: Set<String>
    ) -> String? {
        let added = afterDirectories.subtracting(beforeDirectories)

        let addedWithSkillFile = added.compactMap { name -> String? in
            let candidateURL = root.appendingPathComponent(name, isDirectory: true)
            let skillFileURL = candidateURL.appendingPathComponent("SKILL.md", isDirectory: false)
            return fileManager.fileExists(atPath: skillFileURL.path) ? candidateURL.path : nil
        }
        if addedWithSkillFile.count == 1 {
            return addedWithSkillFile[0]
        }

        if added.count == 1, let only = added.first {
            let candidateURL = root.appendingPathComponent(only, isDirectory: true)
            return candidateURL.path
        }

        let preferred = Self.destinationName(from: source)
        if afterDirectories.contains(preferred) {
            return root.appendingPathComponent(preferred, isDirectory: true).path
        }

        let fallbackName = URL(string: source)?.lastPathComponent
            ?? source.split(separator: "/").last.map(String.init)
        if let fallbackName,
           afterDirectories.contains(fallbackName)
        {
            return root.appendingPathComponent(fallbackName, isDirectory: true).path
        }

        let rootSkillDefinitionURL = root.appendingPathComponent("SKILL.md", isDirectory: false)
        if fileManager.fileExists(atPath: rootSkillDefinitionURL.path) {
            return root.path
        }

        return nil
    }

    private func installMetadataURL(for skillDirectory: URL) -> URL {
        skillDirectory.appendingPathComponent(".codexchat-install.json", isDirectory: false)
    }

    private static func parseSourceReference(source: String, explicitPinnedRef: String?) -> SourceReference {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit = explicitPinnedRef?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty
        {
            return SourceReference(source: trimmedSource, pinnedRef: explicit)
        }

        guard let hashIndex = trimmedSource.lastIndex(of: "#") else {
            return SourceReference(source: trimmedSource, pinnedRef: nil)
        }

        let base = String(trimmedSource[..<hashIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = String(trimmedSource[trimmedSource.index(after: hashIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !base.isEmpty, !ref.isEmpty else {
            return SourceReference(source: trimmedSource, pinnedRef: nil)
        }
        return SourceReference(source: base, pinnedRef: ref)
    }

    private func checkoutPinnedRefIfNeeded(at path: String, pinnedRef: String?) throws -> String {
        guard let pinnedRef = pinnedRef?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pinnedRef.isEmpty
        else {
            return ""
        }
        return try processRunner(["git", "-C", path, "checkout", "--detach", pinnedRef], nil)
    }

    private func writeInstallMetadata(at skillDirectory: URL, metadata: SkillInstallMetadata) throws {
        let payload = InstallMetadataPayload(
            source: metadata.source,
            installer: metadata.installer,
            pinnedRef: metadata.pinnedRef,
            installedAt: metadata.installedAt ?? Date(),
            updatedAt: metadata.updatedAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: installMetadataURL(for: skillDirectory), options: [.atomic])
    }

    private func readInstallMetadata(at skillDirectory: URL) throws -> SkillInstallMetadata {
        let url = installMetadataURL(for: skillDirectory)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SkillCatalogError.installMetadataMissing(skillDirectory.path)
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(InstallMetadataPayload.self, from: data)
        return SkillInstallMetadata(
            source: payload.source,
            installer: payload.installer,
            pinnedRef: payload.pinnedRef,
            installedAt: payload.installedAt,
            updatedAt: payload.updatedAt
        )
    }

    public static func defaultProcessRunner(_ argv: [String], _ cwd: String?) throws -> String {
        let limits = BoundedProcessRunner.Limits.fromEnvironment()
        do {
            return try BoundedProcessRunner.runChecked(argv, cwd: cwd, limits: limits)
        } catch let error as BoundedProcessRunner.CommandError {
            switch error {
            case let .failed(command, output):
                throw SkillCatalogError.commandFailed(command: command, output: output)
            }
        } catch {
            let command = argv.joined(separator: " ")
            throw SkillCatalogError.commandFailed(command: command, output: error.localizedDescription)
        }
    }
}
