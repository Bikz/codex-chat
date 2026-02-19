import Foundation

public struct ModInstallResult: Hashable, Sendable {
    public let source: String
    public let installedDirectoryPath: String
    public let definition: UIModDefinition
    public let packageManifest: ModPackageManifest
    public let manifestSource: ModPackageManifestSource
    public let requestedPermissions: Set<ModPermissionKey>
    public let warnings: [String]

    public init(
        source: String,
        installedDirectoryPath: String,
        definition: UIModDefinition,
        packageManifest: ModPackageManifest,
        manifestSource: ModPackageManifestSource,
        requestedPermissions: Set<ModPermissionKey>,
        warnings: [String]
    ) {
        self.source = source
        self.installedDirectoryPath = installedDirectoryPath
        self.definition = definition
        self.packageManifest = packageManifest
        self.manifestSource = manifestSource
        self.requestedPermissions = requestedPermissions
        self.warnings = warnings
    }
}

public struct ModInstallPreview: Hashable, Sendable {
    public let source: String
    public let definition: UIModDefinition
    public let packageManifest: ModPackageManifest
    public let manifestSource: ModPackageManifestSource
    public let requestedPermissions: Set<ModPermissionKey>
    public let warnings: [String]

    public init(
        source: String,
        definition: UIModDefinition,
        packageManifest: ModPackageManifest,
        manifestSource: ModPackageManifestSource,
        requestedPermissions: Set<ModPermissionKey>,
        warnings: [String]
    ) {
        self.source = source
        self.definition = definition
        self.packageManifest = packageManifest
        self.manifestSource = manifestSource
        self.requestedPermissions = requestedPermissions
        self.warnings = warnings
    }
}

public enum ModInstallServiceError: LocalizedError, Sendable {
    case invalidSource(String)
    case sourceNotFound(String)
    case sourceNotDirectory(String)
    case unsupportedRemoteSource(String)
    case cloneFailed(String)
    case packageRootNotFound
    case existingInstallNotFound(String)
    case existingInstallNotDirectory(String)
    case copyFailed(String)
    case commandFailed(command: String, output: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidSource(source):
            "Invalid mod source: \(source)"
        case let .sourceNotFound(source):
            "Mod source path not found: \(source)"
        case let .sourceNotDirectory(source):
            "Mod source must be a directory: \(source)"
        case let .unsupportedRemoteSource(source):
            "Unsupported remote source URL: \(source). Only GitHub repositories are supported for remote install."
        case let .cloneFailed(detail):
            "Failed to clone mod source: \(detail)"
        case .packageRootNotFound:
            "Source must contain exactly one mod package folder with `codex.mod.json`."
        case let .existingInstallNotFound(path):
            "Existing install path not found: \(path)"
        case let .existingInstallNotDirectory(path):
            "Existing install path must be a directory: \(path)"
        case let .copyFailed(detail):
            "Failed to copy mod package into destination: \(detail)"
        case let .commandFailed(command, output):
            "Command failed (\(command)): \(output)"
        }
    }
}

public final class ModInstallService: @unchecked Sendable {
    public typealias ProcessRunner = @Sendable (_ argv: [String], _ cwd: String?) throws -> String

    private struct StagedSource {
        let rootURL: URL
        let cleanupURL: URL?
        let packageSubpath: String?
    }

    private struct GitHubSourceDescriptor {
        let cloneURL: String
        let branch: String?
        let packageSubpath: String?
    }

    private struct PreparedPackage {
        let source: String
        let packageRootURL: URL
        let resolvedPackage: ResolvedModPackage
        let cleanupURL: URL?
    }

    private let fileManager: FileManager
    private let processRunner: ProcessRunner

    public init(
        fileManager: FileManager = .default,
        processRunner: @escaping ProcessRunner = ModInstallService.defaultProcessRunner
    ) {
        self.fileManager = fileManager
        self.processRunner = processRunner
    }

    public func install(source: String, destinationRootURL: URL) throws -> ModInstallResult {
        try fileManager.createDirectory(at: destinationRootURL, withIntermediateDirectories: true)
        let prepared = try preparePackage(source: source)
        defer {
            if let cleanupURL = prepared.cleanupURL {
                try? fileManager.removeItem(at: cleanupURL)
            }
        }
        let destinationURL = uniqueDestinationURL(
            in: destinationRootURL,
            preferredName: sanitizedDirectoryName(from: prepared.resolvedPackage.manifest.id)
        )

        do {
            try fileManager.copyItem(at: prepared.packageRootURL, to: destinationURL)
        } catch {
            throw ModInstallServiceError.copyFailed(error.localizedDescription)
        }

        return ModInstallResult(
            source: prepared.source,
            installedDirectoryPath: destinationURL.standardizedFileURL.path,
            definition: prepared.resolvedPackage.uiModDefinition,
            packageManifest: prepared.resolvedPackage.manifest,
            manifestSource: prepared.resolvedPackage.manifestSource,
            requestedPermissions: prepared.resolvedPackage.requestedPermissions,
            warnings: prepared.resolvedPackage.warnings
        )
    }

    public func preview(source: String) throws -> ModInstallPreview {
        let prepared = try preparePackage(source: source)
        defer {
            if let cleanupURL = prepared.cleanupURL {
                try? fileManager.removeItem(at: cleanupURL)
            }
        }

        return ModInstallPreview(
            source: prepared.source,
            definition: prepared.resolvedPackage.uiModDefinition,
            packageManifest: prepared.resolvedPackage.manifest,
            manifestSource: prepared.resolvedPackage.manifestSource,
            requestedPermissions: prepared.resolvedPackage.requestedPermissions,
            warnings: prepared.resolvedPackage.warnings
        )
    }

    public func update(source: String, existingInstallURL: URL) throws -> ModInstallResult {
        let normalizedExistingURL = existingInstallURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalizedExistingURL.path, isDirectory: &isDirectory) else {
            throw ModInstallServiceError.existingInstallNotFound(normalizedExistingURL.path)
        }
        guard isDirectory.boolValue else {
            throw ModInstallServiceError.existingInstallNotDirectory(normalizedExistingURL.path)
        }

        let prepared = try preparePackage(source: source)
        defer {
            if let cleanupURL = prepared.cleanupURL {
                try? fileManager.removeItem(at: cleanupURL)
            }
        }

        let parentURL = normalizedExistingURL.deletingLastPathComponent()
        let backupURL = parentURL.appendingPathComponent(
            "\(normalizedExistingURL.lastPathComponent).rollback-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try fileManager.moveItem(at: normalizedExistingURL, to: backupURL)
        } catch {
            throw ModInstallServiceError.copyFailed("Failed to prepare rollback backup: \(error.localizedDescription)")
        }

        do {
            try fileManager.copyItem(at: prepared.packageRootURL, to: normalizedExistingURL)
            try? fileManager.removeItem(at: backupURL)
        } catch let updateError {
            try? fileManager.removeItem(at: normalizedExistingURL)
            do {
                try fileManager.moveItem(at: backupURL, to: normalizedExistingURL)
            } catch let rollbackError {
                let updateMessage = updateError.localizedDescription
                let rollbackMessage = rollbackError.localizedDescription
                let detail = "Update failed and rollback also failed. Manual recovery required. "
                    + "Update error: \(updateMessage); rollback error: \(rollbackMessage)"
                throw ModInstallServiceError.copyFailed(
                    detail
                )
            }
            throw ModInstallServiceError.copyFailed(
                "Update failed and was rolled back: \(updateError.localizedDescription)"
            )
        }

        return ModInstallResult(
            source: prepared.source,
            installedDirectoryPath: normalizedExistingURL.path,
            definition: prepared.resolvedPackage.uiModDefinition,
            packageManifest: prepared.resolvedPackage.manifest,
            manifestSource: prepared.resolvedPackage.manifestSource,
            requestedPermissions: prepared.resolvedPackage.requestedPermissions,
            warnings: prepared.resolvedPackage.warnings
        )
    }

    private func preparePackage(source: String) throws -> PreparedPackage {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            throw ModInstallServiceError.invalidSource(source)
        }

        let staged = try stageSource(trimmedSource)
        let packageRootURL = try resolvePackageRoot(from: staged.rootURL, preferredSubpath: staged.packageSubpath)
        let resolvedPackage = try ModPackageManifestLoader.load(packageRootURL: packageRootURL, fileManager: fileManager)
        return PreparedPackage(
            source: trimmedSource,
            packageRootURL: packageRootURL,
            resolvedPackage: resolvedPackage,
            cleanupURL: staged.cleanupURL
        )
    }

    private func stageSource(_ source: String) throws -> StagedSource {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: source, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ModInstallServiceError.sourceNotDirectory(source)
            }
            return StagedSource(
                rootURL: URL(fileURLWithPath: source, isDirectory: true).standardizedFileURL,
                cleanupURL: nil,
                packageSubpath: nil
            )
        }

        if let url = URL(string: source), url.isFileURL {
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw ModInstallServiceError.sourceNotFound(url.path)
            }
            guard isDirectory.boolValue else {
                throw ModInstallServiceError.sourceNotDirectory(url.path)
            }
            return StagedSource(rootURL: url.standardizedFileURL, cleanupURL: nil, packageSubpath: nil)
        }

        guard let descriptor = parseGitHubSource(source) else {
            throw ModInstallServiceError.unsupportedRemoteSource(source)
        }

        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("codexchat-mod-install-\(UUID().uuidString)", isDirectory: true)

        if let branch = descriptor.branch {
            do {
                _ = try processRunner(
                    ["git", "clone", "--depth", "1", "--branch", branch, descriptor.cloneURL, tempRoot.path],
                    nil
                )
            } catch {
                do {
                    _ = try processRunner(["git", "clone", "--depth", "1", descriptor.cloneURL, tempRoot.path], nil)
                } catch {
                    throw ModInstallServiceError.cloneFailed(error.localizedDescription)
                }
            }
        } else {
            do {
                _ = try processRunner(["git", "clone", "--depth", "1", descriptor.cloneURL, tempRoot.path], nil)
            } catch {
                throw ModInstallServiceError.cloneFailed(error.localizedDescription)
            }
        }

        return StagedSource(rootURL: tempRoot, cleanupURL: tempRoot, packageSubpath: descriptor.packageSubpath)
    }

    private func resolvePackageRoot(from rootURL: URL, preferredSubpath: String?) throws -> URL {
        let normalizedRoot = rootURL.standardizedFileURL
        if let preferredSubpath = normalizedPreferredSubpath(preferredSubpath) {
            let preferredURL = normalizedRoot
                .appendingPathComponent(preferredSubpath, isDirectory: true)
                .standardizedFileURL
            guard preferredURL.path.hasPrefix(normalizedRoot.path + "/"),
                  hasPackageDefinition(in: preferredURL)
            else {
                throw ModInstallServiceError.packageRootNotFound
            }
            return preferredURL
        }

        if hasPackageDefinition(in: normalizedRoot) {
            return normalizedRoot
        }

        let children = try fileManager.contentsOfDirectory(
            at: normalizedRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let candidates = children.filter { child in
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { return false }
            return hasPackageDefinition(in: child)
        }

        guard candidates.count == 1, let candidate = candidates.first else {
            throw ModInstallServiceError.packageRootNotFound
        }

        return candidate.standardizedFileURL
    }

    private func hasPackageDefinition(in directoryURL: URL) -> Bool {
        let codexManifestURL = directoryURL.appendingPathComponent("codex.mod.json", isDirectory: false)
        return fileManager.fileExists(atPath: codexManifestURL.path)
    }

    private func isSupportedRemoteSource(_ source: String) -> Bool {
        parseGitHubSource(source) != nil
    }

    private func parseGitHubSource(_ source: String) -> GitHubSourceDescriptor? {
        if source.hasPrefix("git@github.com:") {
            return GitHubSourceDescriptor(cloneURL: source, branch: nil, packageSubpath: nil)
        }

        guard let url = URL(string: source),
              (url.host ?? "").lowercased() == "github.com"
        else {
            return nil
        }

        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "https" || scheme == "ssh" || scheme == "git" else {
            return nil
        }

        let rawComponents = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard rawComponents.count >= 2 else {
            return nil
        }

        let owner = rawComponents[0]
        let repository = stripGitSuffix(rawComponents[1])
        guard !owner.isEmpty, !repository.isEmpty else {
            return nil
        }

        let cloneURL = "https://github.com/\(owner)/\(repository).git"

        guard rawComponents.count >= 4 else {
            return GitHubSourceDescriptor(cloneURL: cloneURL, branch: nil, packageSubpath: nil)
        }

        let marker = rawComponents[2].lowercased()
        guard marker == "tree" || marker == "blob" else {
            return GitHubSourceDescriptor(cloneURL: cloneURL, branch: nil, packageSubpath: nil)
        }

        let branch = rawComponents[3].removingPercentEncoding ?? rawComponents[3]
        let subpathComponents = rawComponents.dropFirst(4).map { $0.removingPercentEncoding ?? $0 }
        let subpath = subpathComponents.joined(separator: "/")
        let normalizedSubpath = normalizedPreferredSubpath(subpath)

        return GitHubSourceDescriptor(
            cloneURL: cloneURL,
            branch: branch.isEmpty ? nil : branch,
            packageSubpath: normalizedSubpath
        )
    }

    private func stripGitSuffix(_ repository: String) -> String {
        if repository.lowercased().hasSuffix(".git") {
            return String(repository.dropLast(4))
        }
        return repository
    }

    private func normalizedPreferredSubpath(_ subpath: String?) -> String? {
        let trimmed = (subpath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("/") else { return nil }

        let components = NSString(string: trimmed).pathComponents
        if components.contains("..") {
            return nil
        }
        return trimmed
    }

    private func sanitizedDirectoryName(from packageID: String) -> String {
        let trimmed = packageID.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "mod" : trimmed
        let safe = fallback.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "-",
            options: .regularExpression
        )
        return safe.isEmpty ? "mod" : safe
    }

    private func uniqueDestinationURL(in rootURL: URL, preferredName: String) -> URL {
        var candidate = rootURL.appendingPathComponent(preferredName, isDirectory: true)
        var index = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = rootURL.appendingPathComponent("\(preferredName)-\(index)", isDirectory: true)
            index += 1
        }

        return candidate
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

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(bytes: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(bytes: stderrData, encoding: .utf8) ?? ""
        let merged = ([stdout, stderr].joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            let command = argv.joined(separator: " ")
            throw ModInstallServiceError.commandFailed(command: command, output: merged)
        }

        return merged
    }
}
