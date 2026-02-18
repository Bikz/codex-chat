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

enum CodexChatStorageMigrationCoordinator {
    static func performInitialMigrationIfNeeded(
        paths: CodexChatStoragePaths,
        fileManager: FileManager = .default
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
        try importHomeDirectoryIfNeeded(
            source: home.appendingPathComponent(".codex", isDirectory: true),
            destination: paths.codexHomeURL,
            fileManager: fileManager
        )
        try importHomeDirectoryIfNeeded(
            source: home.appendingPathComponent(".agents", isDirectory: true),
            destination: paths.agentsHomeURL,
            fileManager: fileManager
        )

        let stamp = "migration=1\ndate=\(ISO8601DateFormatter().string(from: Date()))\n"
        try stamp.write(to: paths.migrationMarkerURL, atomically: true, encoding: .utf8)
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

    private static func importHomeDirectoryIfNeeded(
        source: URL,
        destination: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }

        if fileManager.fileExists(atPath: destination.path),
           (try? fileManager.contentsOfDirectory(atPath: destination.path).isEmpty) == false
        {
            return
        }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try copyDirectoryContents(
            from: source,
            to: destination,
            overwriteFiles: false,
            fileManager: fileManager
        )
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
        guard fileManager.fileExists(atPath: sourceRoot.path) else {
            return
        }

        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: nil
        )

        while let entry = enumerator?.nextObject() as? URL {
            let relativePath = entry.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
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
