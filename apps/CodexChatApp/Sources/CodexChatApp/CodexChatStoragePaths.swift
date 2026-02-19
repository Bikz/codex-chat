import Foundation

struct CodexChatStoragePaths: Hashable, Sendable {
    static let rootPreferenceKey = "codexchat.storage.root.path"
    static let migrationMarkerFileName = ".storage-migration-v1"
    static let codexHomeNormalizationMarkerFileName = ".codex-home-normalization-v1"
    static let codexHomeLastRepairReportFileName = "codex-home-last-repair-report.json"

    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    var projectsURL: URL {
        rootURL.appendingPathComponent("projects", isDirectory: true)
    }

    var generalProjectURL: URL {
        projectsURL.appendingPathComponent("General", isDirectory: true)
    }

    var globalURL: URL {
        rootURL.appendingPathComponent("global", isDirectory: true)
    }

    var globalModsURL: URL {
        globalURL.appendingPathComponent("mods", isDirectory: true)
    }

    var codexHomeURL: URL {
        globalURL.appendingPathComponent("codex-home", isDirectory: true)
    }

    var codexConfigURL: URL {
        codexHomeURL.appendingPathComponent("config.toml", isDirectory: false)
    }

    var agentsHomeURL: URL {
        globalURL.appendingPathComponent("agents-home", isDirectory: true)
    }

    var systemURL: URL {
        rootURL.appendingPathComponent("system", isDirectory: true)
    }

    var metadataDatabaseURL: URL {
        systemURL.appendingPathComponent("metadata.sqlite", isDirectory: false)
    }

    var modSnapshotsURL: URL {
        systemURL.appendingPathComponent("mod-snapshots", isDirectory: true)
    }

    var migrationMarkerURL: URL {
        systemURL.appendingPathComponent(Self.migrationMarkerFileName, isDirectory: false)
    }

    var codexHomeQuarantineRootURL: URL {
        systemURL.appendingPathComponent("codex-home-quarantine", isDirectory: true)
    }

    var codexHomeNormalizationMarkerURL: URL {
        systemURL.appendingPathComponent(Self.codexHomeNormalizationMarkerFileName, isDirectory: false)
    }

    var codexHomeLastRepairReportURL: URL {
        systemURL.appendingPathComponent(Self.codexHomeLastRepairReportFileName, isDirectory: false)
    }

    static func current(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> CodexChatStoragePaths {
        if let persisted = defaults.string(forKey: rootPreferenceKey),
           !persisted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return CodexChatStoragePaths(rootURL: URL(fileURLWithPath: persisted, isDirectory: true))
        }

        return CodexChatStoragePaths(rootURL: defaultRootURL(fileManager: fileManager))
    }

    static func persistRootURL(_ url: URL, defaults: UserDefaults = .standard) {
        defaults.set(url.standardizedFileURL.path, forKey: rootPreferenceKey)
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("CodexChat", isDirectory: true)
    }

    static func legacyAppSupportRootURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("CodexChat", isDirectory: true)
    }

    func ensureRootStructure(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: globalModsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: codexHomeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: agentsHomeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: systemURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: modSnapshotsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: codexHomeQuarantineRootURL, withIntermediateDirectories: true)
    }

    func uniqueProjectDirectoryURL(
        requestedName: String,
        fileManager: FileManager = .default
    ) -> URL {
        let baseName = Self.sanitizedProjectName(requestedName)
        var candidate = projectsURL.appendingPathComponent(baseName, isDirectory: true)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        var suffix = 2
        while true {
            let nextName = "\(baseName)-\(suffix)"
            candidate = projectsURL.appendingPathComponent(nextName, isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    static func sanitizedProjectName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "New Project"
        }

        let invalid = CharacterSet(charactersIn: "/:\\")
        let controls = CharacterSet.controlCharacters
        let scalars = trimmed.unicodeScalars.map { scalar -> Character in
            if invalid.contains(scalar) || scalar.properties.isWhitespace {
                return "-"
            }
            if controls.contains(scalar) {
                return "-"
            }
            return Character(scalar)
        }

        let collapsed = String(scalars)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-. "))

        return collapsed.isEmpty ? "New Project" : collapsed
    }

    static func isPath(_ path: String, insideRoot rootPath: String) -> Bool {
        let normalizedRoot = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
        let normalizedPath = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path

        if normalizedPath == normalizedRoot {
            return true
        }

        return normalizedPath.hasPrefix(normalizedRoot + "/")
    }
}
