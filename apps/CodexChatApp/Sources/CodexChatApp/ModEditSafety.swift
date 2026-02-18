import CodexKit
import Foundation

/// Helper utilities for enforcing explicit user review when the agent edits mod files.
/// Kept as a small testable surface (used by AppModel, exercised by unit tests).
enum ModEditSafety {
    struct Snapshot: Hashable {
        let createdAt: Date
        let rootURL: URL

        let globalRootPath: String
        let globalSnapshotURL: URL

        let projectRootPath: String
        let projectSnapshotURL: URL?
        let projectRootExisted: Bool
    }

    static func snapshotTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    static func absolutePath(for path: String, projectPath: String) -> String {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        return URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent(path)
            .standardizedFileURL
            .path
    }

    static func isWithin(rootPath: String, path: String) -> Bool {
        let normalizedRoot = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path

        if normalizedPath == normalizedRoot {
            return true
        }
        if normalizedRoot.hasSuffix("/") {
            return normalizedPath.hasPrefix(normalizedRoot)
        }
        return normalizedPath.hasPrefix(normalizedRoot + "/")
    }

    static func filterModChanges(
        changes: [RuntimeFileChange],
        projectPath: String,
        globalRootPath: String?,
        projectRootPath: String
    ) -> [RuntimeFileChange] {
        changes.filter { change in
            let absolute = absolutePath(for: change.path, projectPath: projectPath)
            if let globalRootPath, isWithin(rootPath: globalRootPath, path: absolute) {
                return true
            }
            return isWithin(rootPath: projectRootPath, path: absolute)
        }
    }

    static func captureSnapshot(
        snapshotsRootURL: URL,
        globalRootPath: String,
        projectRootPath: String,
        threadID: UUID,
        startedAt: Date,
        fileManager: FileManager = .default
    ) throws -> Snapshot {
        let timestamp = snapshotTimestamp(startedAt)
        let snapshotRoot = snapshotsRootURL
            .appendingPathComponent("\(timestamp)-\(threadID.uuidString)", isDirectory: true)

        if fileManager.fileExists(atPath: snapshotRoot.path) {
            try fileManager.removeItem(at: snapshotRoot)
        }
        try fileManager.createDirectory(at: snapshotRoot, withIntermediateDirectories: true)

        let globalRootURL = URL(fileURLWithPath: globalRootPath, isDirectory: true)
        let globalSnapshotURL = snapshotRoot.appendingPathComponent("global", isDirectory: true)
        try fileManager.copyItem(at: globalRootURL, to: globalSnapshotURL)

        let projectModsRootURL = URL(fileURLWithPath: projectRootPath, isDirectory: true)
        let projectRootExisted = fileManager.fileExists(atPath: projectModsRootURL.path)

        var projectSnapshotURL: URL?
        if projectRootExisted {
            let dest = snapshotRoot.appendingPathComponent("project", isDirectory: true)
            try fileManager.copyItem(at: projectModsRootURL, to: dest)
            projectSnapshotURL = dest
        }

        return Snapshot(
            createdAt: startedAt,
            rootURL: snapshotRoot,
            globalRootPath: globalRootPath,
            globalSnapshotURL: globalSnapshotURL,
            projectRootPath: projectRootPath,
            projectSnapshotURL: projectSnapshotURL,
            projectRootExisted: projectRootExisted
        )
    }

    static func restore(from snapshot: Snapshot, fileManager: FileManager = .default) throws {
        let globalDestination = URL(fileURLWithPath: snapshot.globalRootPath, isDirectory: true)
        if fileManager.fileExists(atPath: globalDestination.path) {
            try fileManager.removeItem(at: globalDestination)
        }
        try fileManager.createDirectory(
            at: globalDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: snapshot.globalSnapshotURL, to: globalDestination)

        let projectDestination = URL(fileURLWithPath: snapshot.projectRootPath, isDirectory: true)
        if fileManager.fileExists(atPath: projectDestination.path) {
            try fileManager.removeItem(at: projectDestination)
        }

        if snapshot.projectRootExisted {
            guard let projectSnapshotURL = snapshot.projectSnapshotURL else {
                throw CocoaError(.fileReadUnknown)
            }
            try fileManager.copyItem(at: projectSnapshotURL, to: projectDestination)
        }

        discard(snapshot: snapshot, fileManager: fileManager)
    }

    static func discard(snapshot: Snapshot, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: snapshot.rootURL)
    }
}
