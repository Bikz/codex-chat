import Foundation
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public enum SkillLinkManagerError: LocalizedError, Sendable {
    case invalidFolderName(String)
    case sharedStoreRootMissing(String)
    case sharedSkillMissing(String)
    case sharedSkillOutsideStore(path: String, root: String)
    case managedLinkPathOccupied(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidFolderName(name):
            "Invalid skill folder name: \(name)"
        case let .sharedStoreRootMissing(path):
            "Shared skills store is missing: \(path)"
        case let .sharedSkillMissing(path):
            "Shared skill directory is missing: \(path)"
        case let .sharedSkillOutsideStore(path, root):
            "Shared skill path escapes store root (\(path), root: \(root))"
        case let .managedLinkPathOccupied(path):
            "Managed skill link path is occupied by a non-symlink entry: \(path)"
        }
    }
}

public enum SkillStoreKeyBuilder {
    public static func makeKey(source: String, fallbackName: String? = nil) -> String {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = normalizedBaseName(from: trimmedSource, fallbackName: fallbackName)
        let fingerprint = shortFingerprint(for: trimmedSource.isEmpty ? base : trimmedSource)
        return "\(base)-\(fingerprint)"
    }

    private static func normalizedBaseName(from source: String, fallbackName: String?) -> String {
        let fromSource = ownerRepoFromSource(source)
            ?? pathLeafFromSource(source)
            ?? fallbackName
            ?? "skill"
        return sanitizeName(fromSource)
    }

    private static func ownerRepoFromSource(_ source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            let parts = url.path
                .split(separator: "/")
                .map(String.init)
                .filter { !$0.isEmpty }
            guard parts.count >= 2 else {
                return nil
            }
            let owner = parts[0]
            let repo = stripGitSuffix(parts[1])
            guard !owner.isEmpty, !repo.isEmpty else {
                return nil
            }
            return "\(owner)-\(repo)"
        }

        let parts = trimmed
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard parts.count == 2 else {
            return nil
        }
        return "\(parts[0])-\(stripGitSuffix(parts[1]))"
    }

    private static func pathLeafFromSource(_ source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmed), let leaf = url.pathComponents.last {
            return stripGitSuffix(leaf)
        }

        if let leaf = trimmed.split(separator: "/").map(String.init).last {
            return stripGitSuffix(leaf)
        }
        return nil
    }

    private static func stripGitSuffix(_ value: String) -> String {
        value.replacingOccurrences(of: ".git", with: "")
    }

    private static func sanitizeName(_ raw: String) -> String {
        let lowercased = raw.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = lowercased.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? "skill" : collapsed
    }

    private static func shortFingerprint(for value: String) -> String {
        // Deterministic FNV-1a 64-bit hash for stable folder names.
        let offsetBasis: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        var hash = offsetBasis
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        let masked = UInt32(truncatingIfNeeded: hash)
        return String(format: "%08x", masked)
    }
}

public final class SkillLinkManager: @unchecked Sendable {
    private let sharedStoreRootURL: URL
    private let fileManager: FileManager

    public init(sharedStoreRootURL: URL, fileManager: FileManager = .default) {
        self.sharedStoreRootURL = sharedStoreRootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    @discardableResult
    public func ensureProjectSkillLink(
        folderName: String,
        sharedSkillDirectoryURL: URL,
        projectRootURL: URL
    ) throws -> URL {
        let sanitizedFolderName = try Self.sanitizedFolderName(folderName)
        let sharedSkillURL = try validatedSharedSkillURL(sharedSkillDirectoryURL)
        let linkURL = projectSkillLinkURL(projectRootURL: projectRootURL, folderName: sanitizedFolderName)

        try fileManager.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if Self.entryExists(atPath: linkURL.path) {
            let values = try linkURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink == true else {
                throw SkillLinkManagerError.managedLinkPathOccupied(linkURL.path)
            }

            let currentDestination = try resolvedSymlinkDestination(at: linkURL)
            if currentDestination == sharedSkillURL.path {
                return linkURL
            }

            try fileManager.removeItem(at: linkURL)
        }

        try fileManager.createSymbolicLink(atPath: linkURL.path, withDestinationPath: sharedSkillURL.path)
        return linkURL
    }

    @discardableResult
    public func reconcileProjectSkillLink(
        folderName: String,
        sharedSkillDirectoryURL: URL,
        projectRootURL: URL
    ) throws -> Bool {
        let sanitizedFolderName = try Self.sanitizedFolderName(folderName)
        let sharedSkillURL = try validatedSharedSkillURL(sharedSkillDirectoryURL)
        let linkURL = projectSkillLinkURL(projectRootURL: projectRootURL, folderName: sanitizedFolderName)

        let exists = Self.entryExists(atPath: linkURL.path)
        if exists {
            let values = try linkURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink == true else {
                throw SkillLinkManagerError.managedLinkPathOccupied(linkURL.path)
            }

            let currentDestination = try resolvedSymlinkDestination(at: linkURL)
            if currentDestination == sharedSkillURL.path {
                return false
            }
        }

        _ = try ensureProjectSkillLink(
            folderName: sanitizedFolderName,
            sharedSkillDirectoryURL: sharedSkillURL,
            projectRootURL: projectRootURL
        )
        return true
    }

    public func removeProjectSkillLink(folderName: String, projectRootURL: URL) throws {
        let sanitizedFolderName = try Self.sanitizedFolderName(folderName)
        let linkURL = projectSkillLinkURL(projectRootURL: projectRootURL, folderName: sanitizedFolderName)
        guard Self.entryExists(atPath: linkURL.path) else {
            return
        }

        let values = try linkURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink == true else {
            throw SkillLinkManagerError.managedLinkPathOccupied(linkURL.path)
        }
        try fileManager.removeItem(at: linkURL)
    }

    private func projectSkillLinkURL(projectRootURL: URL, folderName: String) -> URL {
        projectRootURL.standardizedFileURL
            .appendingPathComponent(".agents/skills", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private func validatedSharedSkillURL(_ sharedSkillDirectoryURL: URL) throws -> URL {
        let sharedRootPath = sharedStoreRootURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path

        var rootIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sharedRootPath, isDirectory: &rootIsDirectory), rootIsDirectory.boolValue else {
            throw SkillLinkManagerError.sharedStoreRootMissing(sharedRootPath)
        }

        let sharedSkillPath = sharedSkillDirectoryURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sharedSkillPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SkillLinkManagerError.sharedSkillMissing(sharedSkillPath)
        }

        guard Self.path(sharedSkillPath, isInsideRoot: sharedRootPath) else {
            throw SkillLinkManagerError.sharedSkillOutsideStore(path: sharedSkillPath, root: sharedRootPath)
        }

        return URL(fileURLWithPath: sharedSkillPath, isDirectory: true)
    }

    private func resolvedSymlinkDestination(at linkURL: URL) throws -> String {
        let destinationPath = try fileManager.destinationOfSymbolicLink(atPath: linkURL.path)
        let destinationURL: URL = if destinationPath.hasPrefix("/") {
            URL(fileURLWithPath: destinationPath, isDirectory: true)
        } else {
            linkURL.deletingLastPathComponent().appendingPathComponent(destinationPath, isDirectory: true)
        }
        return destinationURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func sanitizedFolderName(_ folderName: String) throws -> String {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\")
        else {
            throw SkillLinkManagerError.invalidFolderName(folderName)
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw SkillLinkManagerError.invalidFolderName(folderName)
        }
        return trimmed
    }

    private static func path(_ path: String, isInsideRoot root: String) -> Bool {
        let normalizedRoot = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.path
        let normalizedPath = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path

        return normalizedPath.hasPrefix(normalizedRoot + "/")
    }

    private static func entryExists(atPath path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }
}
