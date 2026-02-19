import Foundation

enum CodexChatStorageMigrationError: LocalizedError {
    case invalidRootSelection(String)
    case rootCollision([String])

    var errorDescription: String? {
        switch self {
        case let .invalidRootSelection(detail):
            return detail
        case let .rootCollision(entries):
            let preview = entries.prefix(4).joined(separator: ", ")
            return "Selected root already contains non-CodexChat content: \(preview)"
        }
    }
}

struct CodexHomeNormalizationResult: Sendable {
    let executed: Bool
    let forced: Bool
    let reason: String
    let movedEntries: [String]
    let failedEntries: [String]
    let quarantineURL: URL?
    let reportURL: URL

    var movedItemCount: Int {
        movedEntries.count
    }

    var hasChanges: Bool {
        movedItemCount > 0
    }
}

struct CodexHomeNormalizationReport: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: String
    let reason: String
    let forced: Bool
    let codexHomePath: String
    let quarantinePath: String?
    let movedEntries: [String]
    let failedEntries: [String]
}

struct CodexHomeSkillsSymlinkRepairResult: Sendable, Equatable {
    let relinkedEntries: [String]
    let removedEntries: [String]

    var didRepair: Bool {
        !relinkedEntries.isEmpty || !removedEntries.isEmpty
    }
}

enum CodexChatStorageMigrationCoordinator {
    private static let codexHomeImportFiles = [
        "config.toml",
        "auth.json",
        "history.jsonl",
        ".credentials.json",
        "AGENTS.md",
        "AGENTS.override.md",
        "memory.md",
    ]

    private static let codexHomeRuntimeDirectories = [
        "sessions",
        "archived_sessions",
        "shell_snapshots",
        "sqlite",
        "log",
        "tmp",
        "vendor_imports",
        "worktrees",
    ]

    private static let codexHomeRuntimeFiles = [
        ".codex-global-state.json",
        "models_cache.json",
        ".personality_migration",
        "version.json",
    ]

    static func performInitialMigrationIfNeeded(
        paths: CodexChatStoragePaths,
        fileManager: FileManager = .default,
        legacyCodexHomeURL: URL? = nil,
        legacyAgentsHomeURL: URL? = nil
    ) throws {
        try paths.ensureRootStructure(fileManager: fileManager)

        if fileManager.fileExists(atPath: paths.migrationMarkerURL.path) {
            return
        }

        if let legacyRoot = try? CodexChatStoragePaths.legacyAppSupportRootURL(fileManager: fileManager),
           fileManager.fileExists(atPath: legacyRoot.path),
           legacyRoot.standardizedFileURL.path != paths.rootURL.path
        {
            try migrateLegacyAppSupport(
                from: legacyRoot,
                to: paths,
                fileManager: fileManager
            )
        }

        let home = fileManager.homeDirectoryForCurrentUser
        let codexSource = legacyCodexHomeURL ?? home.appendingPathComponent(".codex", isDirectory: true)
        let agentsSource = legacyAgentsHomeURL ?? home.appendingPathComponent(".agents", isDirectory: true)

        try importLegacyCodexHomeArtifactsIfNeeded(
            source: codexSource,
            destination: paths.codexHomeURL,
            fileManager: fileManager
        )
        try importLegacyAgentsHomeArtifactsIfNeeded(
            source: agentsSource,
            destination: paths.agentsHomeURL,
            fileManager: fileManager
        )

        let stamp = "migration=1\ndate=\(ISO8601DateFormatter().string(from: Date()))\n"
        try stamp.write(to: paths.migrationMarkerURL, atomically: true, encoding: .utf8)
    }

    static func normalizeManagedCodexHome(
        paths: CodexChatStoragePaths,
        force: Bool,
        reason: String,
        fileManager: FileManager = .default
    ) throws -> CodexHomeNormalizationResult {
        try paths.ensureRootStructure(fileManager: fileManager)

        if !force, fileManager.fileExists(atPath: paths.codexHomeNormalizationMarkerURL.path) {
            let previousReport = try? readLastCodexHomeNormalizationReport(paths: paths, fileManager: fileManager)
            return CodexHomeNormalizationResult(
                executed: false,
                forced: false,
                reason: "already-normalized",
                movedEntries: [],
                failedEntries: [],
                quarantineURL: previousReport.flatMap { report in
                    guard let path = report.quarantinePath else { return nil }
                    return URL(fileURLWithPath: path, isDirectory: true)
                },
                reportURL: paths.codexHomeLastRepairReportURL
            )
        }

        var movedEntries: [String] = []
        var failedEntries: [String] = []
        var quarantineURL: URL?
        let timestamp = quarantineTimestamp()

        for directory in codexHomeRuntimeDirectories {
            moveCodexHomeEntryIfPresent(
                entryName: directory,
                paths: paths,
                timestamp: timestamp,
                quarantineURL: &quarantineURL,
                movedEntries: &movedEntries,
                failedEntries: &failedEntries,
                fileManager: fileManager
            )
        }

        for file in codexHomeRuntimeFiles {
            moveCodexHomeEntryIfPresent(
                entryName: file,
                paths: paths,
                timestamp: timestamp,
                quarantineURL: &quarantineURL,
                movedEntries: &movedEntries,
                failedEntries: &failedEntries,
                fileManager: fileManager
            )
        }

        let report = CodexHomeNormalizationReport(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            reason: reason,
            forced: force,
            codexHomePath: paths.codexHomeURL.path,
            quarantinePath: quarantineURL?.path,
            movedEntries: movedEntries,
            failedEntries: failedEntries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reportData = try encoder.encode(report)
        try reportData.write(to: paths.codexHomeLastRepairReportURL, options: .atomic)

        let marker = "version=1\ndate=\(ISO8601DateFormatter().string(from: Date()))\nreason=\(reason)\nforced=\(force)\nmoved=\(movedEntries.count)\n"
        try marker.write(to: paths.codexHomeNormalizationMarkerURL, atomically: true, encoding: .utf8)

        return CodexHomeNormalizationResult(
            executed: true,
            forced: force,
            reason: reason,
            movedEntries: movedEntries,
            failedEntries: failedEntries,
            quarantineURL: quarantineURL,
            reportURL: paths.codexHomeLastRepairReportURL
        )
    }

    static func readLastCodexHomeNormalizationReport(
        paths: CodexChatStoragePaths,
        fileManager: FileManager = .default
    ) throws -> CodexHomeNormalizationReport? {
        guard fileManager.fileExists(atPath: paths.codexHomeLastRepairReportURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: paths.codexHomeLastRepairReportURL)
        return try JSONDecoder().decode(CodexHomeNormalizationReport.self, from: data)
    }

    static func repairManagedCodexHomeSkillSymlinksIfNeeded(
        paths: CodexChatStoragePaths,
        fileManager: FileManager = .default
    ) throws -> CodexHomeSkillsSymlinkRepairResult {
        let skillsRoot = paths.codexHomeURL.appendingPathComponent("skills", isDirectory: true)
        guard fileManager.fileExists(atPath: skillsRoot.path) else {
            return CodexHomeSkillsSymlinkRepairResult(relinkedEntries: [], removedEntries: [])
        }

        let entries = try fileManager.contentsOfDirectory(
            at: skillsRoot,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        var relinkedEntries: [String] = []
        var removedEntries: [String] = []

        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink == true else {
                continue
            }

            // fileExists resolves symlinks; false means the link target is stale.
            guard !fileManager.fileExists(atPath: entry.path) else {
                continue
            }

            let skillName = entry.lastPathComponent
            let managedTarget = paths.agentsHomeURL
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent(skillName, isDirectory: true)

            try fileManager.removeItem(at: entry)
            if fileManager.fileExists(atPath: managedTarget.path) {
                try fileManager.createSymbolicLink(
                    atPath: entry.path,
                    withDestinationPath: managedTarget.path
                )
                relinkedEntries.append(skillName)
            } else {
                removedEntries.append(skillName)
            }
        }

        return CodexHomeSkillsSymlinkRepairResult(
            relinkedEntries: relinkedEntries.sorted(),
            removedEntries: removedEntries.sorted()
        )
    }

    static func validateRootSelection(
        newRootURL: URL,
        currentRootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let rootPath = newRootURL.standardizedFileURL.path
        let currentPath = currentRootURL.standardizedFileURL.path

        if rootPath == currentPath {
            throw CodexChatStorageMigrationError.invalidRootSelection("Selected root is already active.")
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: rootPath, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw CodexChatStorageMigrationError.invalidRootSelection("Selected path is not a directory.")
        }

        if CodexChatStoragePaths.isPath(rootPath, insideRoot: currentPath)
            || CodexChatStoragePaths.isPath(currentPath, insideRoot: rootPath)
        {
            throw CodexChatStorageMigrationError.invalidRootSelection(
                "Selected root cannot be nested inside the current root (or vice versa)."
            )
        }
    }

    static func unexpectedTopLevelEntries(
        in rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> [String] {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }

        let children = try fileManager.contentsOfDirectory(atPath: rootURL.path)
        let allowed = Set(["projects", "global", "system"])

        return children
            .filter { !$0.hasPrefix(".") }
            .filter { !allowed.contains($0) }
            .sorted()
    }

    static func migrateManagedRoot(
        from oldPaths: CodexChatStoragePaths,
        to newPaths: CodexChatStoragePaths,
        fileManager: FileManager = .default
    ) throws {
        if oldPaths.rootURL.standardizedFileURL.path == newPaths.rootURL.standardizedFileURL.path {
            return
        }

        try newPaths.ensureRootStructure(fileManager: fileManager)

        guard fileManager.fileExists(atPath: oldPaths.rootURL.path) else {
            return
        }

        try copyDirectoryContents(
            from: oldPaths.rootURL,
            to: newPaths.rootURL,
            overwriteFiles: true,
            fileManager: fileManager
        )
    }

    static func deleteRootIfExists(_ rootURL: URL, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return
        }
        try fileManager.removeItem(at: rootURL)
    }

    static func syncSQLiteFiles(
        sourceSQLiteURL: URL,
        destinationSQLiteURL: URL,
        overwriteExisting: Bool,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: sourceSQLiteURL.path) else {
            return
        }

        try fileManager.createDirectory(at: destinationSQLiteURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destinationSQLiteURL.path), overwriteExisting {
            try fileManager.removeItem(at: destinationSQLiteURL)
        }
        if !fileManager.fileExists(atPath: destinationSQLiteURL.path) {
            try fileManager.copyItem(at: sourceSQLiteURL, to: destinationSQLiteURL)
        }

        let suffixes = ["-wal", "-shm"]
        for suffix in suffixes {
            let source = URL(fileURLWithPath: sourceSQLiteURL.path + suffix, isDirectory: false)
            let destination = URL(fileURLWithPath: destinationSQLiteURL.path + suffix, isDirectory: false)

            guard fileManager.fileExists(atPath: source.path) else {
                continue
            }

            if fileManager.fileExists(atPath: destination.path), overwriteExisting {
                try fileManager.removeItem(at: destination)
            }

            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.copyItem(at: source, to: destination)
            }
        }
    }

    private static func migrateLegacyAppSupport(
        from legacyRoot: URL,
        to paths: CodexChatStoragePaths,
        fileManager: FileManager
    ) throws {
        let legacyMetadata = legacyRoot.appendingPathComponent("metadata.sqlite", isDirectory: false)
        try copySQLiteFilesIfDestinationMissing(
            sourceSQLiteURL: legacyMetadata,
            destinationSQLiteURL: paths.metadataDatabaseURL,
            fileManager: fileManager
        )

        let legacySnapshots = legacyRoot.appendingPathComponent("ModSnapshots", isDirectory: true)
        if fileManager.fileExists(atPath: legacySnapshots.path) {
            try copyDirectoryContents(
                from: legacySnapshots,
                to: paths.modSnapshotsURL,
                overwriteFiles: false,
                fileManager: fileManager
            )
        }

        let legacyGlobalMods = legacyRoot
            .appendingPathComponent("Mods", isDirectory: true)
            .appendingPathComponent("Global", isDirectory: true)
        if fileManager.fileExists(atPath: legacyGlobalMods.path) {
            try copyDirectoryContents(
                from: legacyGlobalMods,
                to: paths.globalModsURL,
                overwriteFiles: false,
                fileManager: fileManager
            )
        }

        let legacyGeneral = legacyRoot.appendingPathComponent("general", isDirectory: true)
        if fileManager.fileExists(atPath: legacyGeneral.path) {
            try copyDirectoryContents(
                from: legacyGeneral,
                to: paths.generalProjectURL,
                overwriteFiles: false,
                fileManager: fileManager
            )
        }
    }

    private static func importLegacyCodexHomeArtifactsIfNeeded(
        source: URL,
        destination: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        for fileName in codexHomeImportFiles {
            let sourceURL = source.appendingPathComponent(fileName, isDirectory: false)
            let destinationURL = destination.appendingPathComponent(fileName, isDirectory: false)
            try copyFileIfMissing(source: sourceURL, destination: destinationURL, fileManager: fileManager)
        }

        let sourceSkills = source.appendingPathComponent("skills", isDirectory: true)
        let destinationSkills = destination.appendingPathComponent("skills", isDirectory: true)
        if fileManager.fileExists(atPath: sourceSkills.path) {
            try copyDirectoryContents(
                from: sourceSkills,
                to: destinationSkills,
                overwriteFiles: false,
                fileManager: fileManager
            )
        }
    }

    private static func importLegacyAgentsHomeArtifactsIfNeeded(
        source: URL,
        destination: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }

        let sourceSkills = source.appendingPathComponent("skills", isDirectory: true)
        let destinationSkills = destination.appendingPathComponent("skills", isDirectory: true)
        if fileManager.fileExists(atPath: sourceSkills.path) {
            try copyDirectoryContents(
                from: sourceSkills,
                to: destinationSkills,
                overwriteFiles: false,
                fileManager: fileManager
            )
        }
    }

    private static func copyFileIfMissing(
        source: URL,
        destination: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return
        }

        guard !fileManager.fileExists(atPath: destination.path) else {
            return
        }

        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func moveCodexHomeEntryIfPresent(
        entryName: String,
        paths: CodexChatStoragePaths,
        timestamp: String,
        quarantineURL: inout URL?,
        movedEntries: inout [String],
        failedEntries: inout [String],
        fileManager: FileManager
    ) {
        let sourceURL = paths.codexHomeURL.appendingPathComponent(entryName, isDirectory: false)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return
        }

        do {
            let destinationRoot = try ensureQuarantineDirectoryIfNeeded(
                existingURL: quarantineURL,
                quarantineRootURL: paths.codexHomeQuarantineRootURL,
                timestamp: timestamp,
                fileManager: fileManager
            )
            quarantineURL = destinationRoot
            let destinationURL = uniqueQuarantineDestination(
                for: entryName,
                destinationRoot: destinationRoot,
                fileManager: fileManager
            )
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            movedEntries.append(entryName)
        } catch {
            failedEntries.append("\(entryName): \(error.localizedDescription)")
        }
    }

    private static func ensureQuarantineDirectoryIfNeeded(
        existingURL: URL?,
        quarantineRootURL: URL,
        timestamp: String,
        fileManager: FileManager
    ) throws -> URL {
        if let existingURL {
            return existingURL
        }

        try fileManager.createDirectory(at: quarantineRootURL, withIntermediateDirectories: true)
        let destination = quarantineRootURL.appendingPathComponent(timestamp, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        return destination
    }

    private static func uniqueQuarantineDestination(
        for entryName: String,
        destinationRoot: URL,
        fileManager: FileManager
    ) -> URL {
        var candidate = destinationRoot.appendingPathComponent(entryName, isDirectory: false)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        var suffix = 2
        while true {
            let nextName = "\(entryName)-\(suffix)"
            candidate = destinationRoot.appendingPathComponent(nextName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func quarantineTimestamp(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func copySQLiteFilesIfDestinationMissing(
        sourceSQLiteURL: URL,
        destinationSQLiteURL: URL,
        fileManager: FileManager
    ) throws {
        guard !fileManager.fileExists(atPath: destinationSQLiteURL.path) else {
            return
        }
        try syncSQLiteFiles(
            sourceSQLiteURL: sourceSQLiteURL,
            destinationSQLiteURL: destinationSQLiteURL,
            overwriteExisting: false,
            fileManager: fileManager
        )
    }

    private static func copyDirectoryContents(
        from sourceRoot: URL,
        to destinationRoot: URL,
        overwriteFiles: Bool,
        fileManager: FileManager
    ) throws {
        let normalizedSourceRoot = sourceRoot.standardizedFileURL
        guard fileManager.fileExists(atPath: normalizedSourceRoot.path) else {
            return
        }

        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let enumerator = fileManager.enumerator(
            at: normalizedSourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: nil
        )

        while let entry = enumerator?.nextObject() as? URL {
            let normalizedEntryPath = entry.standardizedFileURL.path
            let prefix = normalizedSourceRoot.path + "/"
            guard normalizedEntryPath.hasPrefix(prefix) else {
                continue
            }

            let relativePath = String(normalizedEntryPath.dropFirst(prefix.count))
            if relativePath.isEmpty {
                continue
            }

            let destination = destinationRoot.appendingPathComponent(relativePath, isDirectory: false)
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey])

            if values.isDirectory == true {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }

            let destinationParent = destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: destination.path) {
                if !overwriteFiles {
                    continue
                }
                try fileManager.removeItem(at: destination)
            }

            try fileManager.copyItem(at: entry, to: destination)
        }
    }
}
