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

struct SharedCodexHomeHandoffResult: Sendable {
    let executed: Bool
    let copiedEntries: [String]
    let skippedEntries: [String]
    let failedEntries: [String]
    let reportURL: URL
}

struct SharedCodexHomeHandoffReport: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: String
    let source: String
    let activeCodexHomePath: String
    let activeAgentsHomePath: String
    let legacyManagedCodexHomePath: String
    let legacyManagedAgentsHomePath: String
    let copiedEntries: [String]
    let skippedEntries: [String]
    let failedEntries: [String]
}

struct LegacyManagedHomesArchiveResult: Sendable {
    let executed: Bool
    let archivedEntries: [String]
    let skippedEntries: [String]
    let failedEntries: [String]
    let archiveRootURL: URL?
    let reportURL: URL
}

struct LegacyManagedHomesArchiveReport: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: String
    let archiveRootPath: String?
    let legacyManagedCodexHomePath: String
    let legacyManagedAgentsHomePath: String
    let archivedEntries: [String]
    let skippedEntries: [String]
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
    private static let codexArtifactEntries = [
        "config.toml",
        "auth.json",
        "history.jsonl",
        ".credentials.json",
        "AGENTS.md",
        "AGENTS.override.md",
        "memory.md",
        "skills",
    ]

    private static let agentsArtifactEntries = [
        "skills",
    ]

    static func performInitialMigrationIfNeeded(
        paths: CodexChatStoragePaths,
        fileManager: FileManager = .default,
        legacyCodexHomeURL _: URL? = nil,
        legacyAgentsHomeURL _: URL? = nil
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

        let stamp = "migration=1\ndate=\(ISO8601DateFormatter().string(from: Date()))\n"
        try stamp.write(to: paths.migrationMarkerURL, atomically: true, encoding: .utf8)
    }

    static func performSharedHomeHandoffIfNeeded(
        paths: CodexChatStoragePaths,
        homes: ResolvedCodexHomes,
        fileManager: FileManager = .default
    ) throws -> SharedCodexHomeHandoffResult {
        try paths.ensureRootStructure(fileManager: fileManager)
        try fileManager.createDirectory(at: homes.activeCodexHomeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: homes.activeAgentsHomeURL, withIntermediateDirectories: true)

        if let previous = try readLastSharedCodexHomeHandoffReport(paths: paths, fileManager: fileManager),
           previous.source == homes.source.rawValue,
           previous.activeCodexHomePath == homes.activeCodexHomeURL.path,
           previous.activeAgentsHomePath == homes.activeAgentsHomeURL.path
        {
            return SharedCodexHomeHandoffResult(
                executed: false,
                copiedEntries: [],
                skippedEntries: previous.skippedEntries,
                failedEntries: previous.failedEntries,
                reportURL: paths.sharedCodexHomeHandoffReportURL
            )
        }

        var copiedEntries: [String] = []
        var skippedEntries: [String] = []
        var failedEntries: [String] = []

        try importArtifactsIfMissing(
            entryNames: codexArtifactEntries,
            sourceRoot: homes.legacyManagedCodexHomeURL,
            destinationRoot: homes.activeCodexHomeURL,
            fileManager: fileManager,
            copiedEntries: &copiedEntries,
            skippedEntries: &skippedEntries,
            failedEntries: &failedEntries
        )

        try importArtifactsIfMissing(
            entryNames: agentsArtifactEntries,
            sourceRoot: homes.legacyManagedAgentsHomeURL,
            destinationRoot: homes.activeAgentsHomeURL,
            fileManager: fileManager,
            copiedEntries: &copiedEntries,
            skippedEntries: &skippedEntries,
            failedEntries: &failedEntries
        )

        let report = SharedCodexHomeHandoffReport(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            source: homes.source.rawValue,
            activeCodexHomePath: homes.activeCodexHomeURL.path,
            activeAgentsHomePath: homes.activeAgentsHomeURL.path,
            legacyManagedCodexHomePath: homes.legacyManagedCodexHomeURL.path,
            legacyManagedAgentsHomePath: homes.legacyManagedAgentsHomeURL.path,
            copiedEntries: copiedEntries.sorted(),
            skippedEntries: skippedEntries.sorted(),
            failedEntries: failedEntries.sorted()
        )
        try write(report: report, to: paths.sharedCodexHomeHandoffReportURL)

        let marker = """
        version=1
        date=\(report.generatedAt)
        source=\(homes.source.rawValue)
        active_codex_home=\(homes.activeCodexHomeURL.path)
        active_agents_home=\(homes.activeAgentsHomeURL.path)
        copied=\(copiedEntries.count)
        skipped=\(skippedEntries.count)
        failed=\(failedEntries.count)
        """
        try marker.write(to: paths.sharedCodexHomeHandoffMarkerURL, atomically: true, encoding: .utf8)

        return SharedCodexHomeHandoffResult(
            executed: true,
            copiedEntries: copiedEntries.sorted(),
            skippedEntries: skippedEntries.sorted(),
            failedEntries: failedEntries.sorted(),
            reportURL: paths.sharedCodexHomeHandoffReportURL
        )
    }

    static func readLastSharedCodexHomeHandoffReport(
        paths: CodexChatStoragePaths,
        fileManager: FileManager = .default
    ) throws -> SharedCodexHomeHandoffReport? {
        guard fileManager.fileExists(atPath: paths.sharedCodexHomeHandoffReportURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: paths.sharedCodexHomeHandoffReportURL)
        return try JSONDecoder().decode(SharedCodexHomeHandoffReport.self, from: data)
    }

    static func archiveLegacyManagedHomes(
        paths: CodexChatStoragePaths,
        fileManager: FileManager = .default
    ) throws -> LegacyManagedHomesArchiveResult {
        try paths.ensureRootStructure(fileManager: fileManager)

        let sources: [(label: String, url: URL)] = [
            ("codex-home", paths.legacyManagedCodexHomeURL),
            ("agents-home", paths.legacyManagedAgentsHomeURL),
        ]

        var archivedEntries: [String] = []
        var skippedEntries: [String] = []
        var failedEntries: [String] = []
        var archiveRootURL: URL?

        for source in sources {
            guard fileManager.fileExists(atPath: source.url.path) else {
                skippedEntries.append("\(source.label):missing")
                continue
            }

            if archiveRootURL == nil {
                let timestamp = archiveTimestamp()
                let root = paths.legacyManagedHomesArchiveRootURL.appendingPathComponent(timestamp, isDirectory: true)
                try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
                archiveRootURL = root
            }

            guard let archiveRootURL else { continue }
            let destinationURL = uniqueArchiveDestination(
                named: source.label,
                archiveRootURL: archiveRootURL,
                fileManager: fileManager
            )

            do {
                try fileManager.moveItem(at: source.url, to: destinationURL)
                archivedEntries.append(source.label)
            } catch {
                failedEntries.append("\(source.label): \(error.localizedDescription)")
            }
        }

        let report = LegacyManagedHomesArchiveReport(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            archiveRootPath: archiveRootURL?.path,
            legacyManagedCodexHomePath: paths.legacyManagedCodexHomeURL.path,
            legacyManagedAgentsHomePath: paths.legacyManagedAgentsHomeURL.path,
            archivedEntries: archivedEntries.sorted(),
            skippedEntries: skippedEntries.sorted(),
            failedEntries: failedEntries.sorted()
        )
        try write(report: report, to: paths.legacyManagedHomesLastArchiveReportURL)

        return LegacyManagedHomesArchiveResult(
            executed: archiveRootURL != nil,
            archivedEntries: archivedEntries.sorted(),
            skippedEntries: skippedEntries.sorted(),
            failedEntries: failedEntries.sorted(),
            archiveRootURL: archiveRootURL,
            reportURL: paths.legacyManagedHomesLastArchiveReportURL
        )
    }

    static func readLastLegacyManagedHomesArchiveReport(
        paths: CodexChatStoragePaths,
        fileManager: FileManager = .default
    ) throws -> LegacyManagedHomesArchiveReport? {
        guard fileManager.fileExists(atPath: paths.legacyManagedHomesLastArchiveReportURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: paths.legacyManagedHomesLastArchiveReportURL)
        return try JSONDecoder().decode(LegacyManagedHomesArchiveReport.self, from: data)
    }

    static func repairManagedCodexHomeSkillSymlinksIfNeeded(
        paths: CodexChatStoragePaths,
        fileManager: FileManager = .default
    ) throws -> CodexHomeSkillsSymlinkRepairResult {
        let skillsRoot = paths.legacyManagedCodexHomeURL.appendingPathComponent("skills", isDirectory: true)
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

            guard !fileManager.fileExists(atPath: entry.path) else {
                continue
            }

            let skillName = entry.lastPathComponent
            let managedTarget = paths.legacyManagedAgentsHomeURL
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

    private static func importArtifactsIfMissing(
        entryNames: [String],
        sourceRoot: URL,
        destinationRoot: URL,
        fileManager: FileManager,
        copiedEntries: inout [String],
        skippedEntries: inout [String],
        failedEntries: inout [String]
    ) throws {
        guard fileManager.fileExists(atPath: sourceRoot.path) else {
            skippedEntries.append("\(sourceRoot.lastPathComponent):missing-source")
            return
        }

        for entryName in entryNames {
            let sourceURL = sourceRoot.appendingPathComponent(entryName, isDirectory: false)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                skippedEntries.append("\(entryName):missing")
                continue
            }

            let destinationURL = destinationRoot.appendingPathComponent(entryName, isDirectory: false)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
                skippedEntries.append("\(entryName):missing")
                continue
            }

            if isDirectory.boolValue {
                let report = try copyDirectoryEntriesIfMissing(
                    from: sourceURL,
                    to: destinationURL,
                    fileManager: fileManager
                )
                copiedEntries.append(contentsOf: report.copied.map { "\(entryName)/\($0)" })
                skippedEntries.append(contentsOf: report.skipped.map { "\(entryName)/\($0)" })
                failedEntries.append(contentsOf: report.failed.map { "\(entryName)/\($0)" })
            } else if fileManager.fileExists(atPath: destinationURL.path) {
                skippedEntries.append("\(entryName):exists")
            } else {
                do {
                    try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                    copiedEntries.append(entryName)
                } catch {
                    failedEntries.append("\(entryName): \(error.localizedDescription)")
                }
            }
        }
    }

    private static func copyDirectoryEntriesIfMissing(
        from sourceRoot: URL,
        to destinationRoot: URL,
        fileManager: FileManager
    ) throws -> (copied: [String], skipped: [String], failed: [String]) {
        var copied: [String] = []
        var skipped: [String] = []
        var failed: [String] = []

        guard fileManager.fileExists(atPath: sourceRoot.path) else {
            return (copied, skipped, failed)
        }

        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: nil
        )
        let prefix = sourceRoot.standardizedFileURL.path + "/"

        while let entry = enumerator?.nextObject() as? URL {
            let normalizedPath = entry.standardizedFileURL.path
            guard normalizedPath.hasPrefix(prefix) else {
                continue
            }

            let relativePath = String(normalizedPath.dropFirst(prefix.count))
            guard !relativePath.isEmpty else {
                continue
            }

            let destinationURL = destinationRoot.appendingPathComponent(relativePath, isDirectory: false)
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey])

            if fileManager.fileExists(atPath: destinationURL.path) {
                skipped.append("\(relativePath):exists")
                continue
            }

            do {
                if values.isDirectory == true {
                    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                } else {
                    try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.copyItem(at: entry, to: destinationURL)
                }
                copied.append(relativePath)
            } catch {
                failed.append("\(relativePath): \(error.localizedDescription)")
            }
        }

        return (copied, skipped, failed)
    }

    private static func uniqueArchiveDestination(
        named name: String,
        archiveRootURL: URL,
        fileManager: FileManager
    ) -> URL {
        var candidate = archiveRootURL.appendingPathComponent(name, isDirectory: true)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        var suffix = 2
        while true {
            candidate = archiveRootURL.appendingPathComponent("\(name)-\(suffix)", isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func archiveTimestamp(date: Date = Date()) -> String {
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

    private static func write(report: some Encodable, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }
}
