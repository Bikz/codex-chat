import CodexChatCore
import Foundation

public final class DesktopCleanupAction: ComputerActionProvider, @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectoryProvider: @Sendable () -> URL

    public init(
        fileManager: FileManager = .default,
        homeDirectoryProvider: @escaping @Sendable () -> URL = { FileManager.default.homeDirectoryForCurrentUser }
    ) {
        self.fileManager = fileManager
        self.homeDirectoryProvider = homeDirectoryProvider
    }

    public let actionID = "desktop.cleanup"
    public let displayName = "Desktop Cleanup"
    public let safetyLevel: ComputerActionSafetyLevel = .destructive
    public let requiresConfirmation = true

    public func preview(request: ComputerActionRequest) async throws -> ComputerActionPreviewArtifact {
        let desktopURL = resolveDesktopURL(arguments: request.arguments)
        guard fileManager.fileExists(atPath: desktopURL.path) else {
            throw ComputerActionError.invalidArguments("Desktop path does not exist: \(desktopURL.path)")
        }

        let entries = try fileManager.contentsOfDirectory(
            at: desktopURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let operations = try entries.compactMap { candidate -> DesktopCleanupOperation? in
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            guard values.isRegularFile == true, values.isDirectory != true else {
                return nil
            }

            let folder = Self.destinationFolder(for: candidate.pathExtension)
            let destinationDirectory = desktopURL.appendingPathComponent(folder, isDirectory: true)
            let destination = destinationDirectory.appendingPathComponent(candidate.lastPathComponent, isDirectory: false)

            return DesktopCleanupOperation(
                sourcePath: candidate.path,
                destinationPath: destination.path,
                destinationFolder: folder
            )
        }

        let summary = operations.isEmpty
            ? "No cleanup actions needed."
            : "Prepared \(operations.count) move operation(s)."

        let markdown: String
        if operations.isEmpty {
            markdown = "Your desktop is already organized."
        } else {
            let grouped = Dictionary(grouping: operations, by: \ .destinationFolder)
            let lines = grouped
                .keys
                .sorted()
                .map { folder in
                    let count = grouped[folder]?.count ?? 0
                    return "- \(folder): \(count) file(s)"
                }
                .joined(separator: "\n")
            markdown = "Planned moves:\n\n\(lines)"
        }

        return ComputerActionPreviewArtifact(
            actionID: actionID,
            runContextID: request.runContextID,
            title: "Desktop Cleanup Preview",
            summary: summary,
            detailsMarkdown: markdown,
            data: [
                "desktopPath": desktopURL.path,
                "operations": Self.encodeOperations(operations),
            ]
        )
    }

    public func execute(
        request: ComputerActionRequest,
        preview: ComputerActionPreviewArtifact
    ) async throws -> ComputerActionExecutionResult {
        try validate(preview: preview, request: request)

        guard let operationsText = preview.data["operations"] else {
            throw ComputerActionError.invalidPreviewArtifact
        }

        let operations = try Self.decodeOperations(operationsText)
        var applied: [DesktopCleanupUndoEntry] = []

        for operation in operations {
            let sourceURL = URL(fileURLWithPath: operation.sourcePath, isDirectory: false)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }

            let destinationURL = URL(fileURLWithPath: operation.destinationPath, isDirectory: false)
            let destinationDirectory = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

            let uniqueDestination = uniqueDestinationURL(for: destinationURL)
            try fileManager.moveItem(at: sourceURL, to: uniqueDestination)
            applied.append(
                DesktopCleanupUndoEntry(
                    sourcePath: sourceURL.path,
                    movedPath: uniqueDestination.path
                )
            )
        }

        let manifestDirectory = resolveManifestDirectory(arguments: request.arguments, artifactDirectoryPath: request.artifactDirectoryPath)
        try fileManager.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        let manifestURL = manifestDirectory.appendingPathComponent("desktop-cleanup-\(request.runContextID).json", isDirectory: false)
        let manifest = DesktopCleanupUndoManifest(entries: applied)
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: manifestURL, options: [.atomic])

        let summary = applied.isEmpty
            ? "No files were moved during cleanup."
            : "Moved \(applied.count) file(s) from Desktop into organized folders."
        let details = applied.isEmpty
            ? "No changes were necessary."
            : "Undo manifest written to `\(manifestURL.path)`"

        return ComputerActionExecutionResult(
            actionID: actionID,
            runContextID: request.runContextID,
            summary: summary,
            detailsMarkdown: details,
            metadata: [
                "undoManifestPath": manifestURL.path,
                "movedCount": String(applied.count),
            ]
        )
    }

    public func undoLastCleanup(manifestPath: String) throws -> Int {
        let manifestURL = URL(fileURLWithPath: manifestPath, isDirectory: false)
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(DesktopCleanupUndoManifest.self, from: data)

        var restoredCount = 0
        for entry in manifest.entries.reversed() {
            let movedURL = URL(fileURLWithPath: entry.movedPath, isDirectory: false)
            let sourceURL = URL(fileURLWithPath: entry.sourcePath, isDirectory: false)

            guard fileManager.fileExists(atPath: movedURL.path) else {
                continue
            }

            try fileManager.createDirectory(
                at: sourceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let destination = uniqueDestinationURL(for: sourceURL)
            try fileManager.moveItem(at: movedURL, to: destination)
            restoredCount += 1
        }

        return restoredCount
    }

    private func resolveDesktopURL(arguments: [String: String]) -> URL {
        if let overridePath = arguments["desktopPath"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty
        {
            return URL(fileURLWithPath: overridePath, isDirectory: true).standardizedFileURL
        }

        return homeDirectoryProvider()
            .appendingPathComponent("Desktop", isDirectory: true)
            .standardizedFileURL
    }

    private func resolveManifestDirectory(arguments: [String: String], artifactDirectoryPath: String?) -> URL {
        if let explicit = arguments["undoDirectoryPath"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty
        {
            return URL(fileURLWithPath: explicit, isDirectory: true).standardizedFileURL
        }

        if let artifactDirectoryPath,
           !artifactDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return URL(fileURLWithPath: artifactDirectoryPath, isDirectory: true)
                .appendingPathComponent("cleanup-undo", isDirectory: true)
                .standardizedFileURL
        }

        return fileManager.temporaryDirectory
            .appendingPathComponent("codexchat-cleanup-undo", isDirectory: true)
            .standardizedFileURL
    }

    private func uniqueDestinationURL(for url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path) else {
            return url
        }

        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(baseName)-\(index)" : "\(baseName)-\(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private static func destinationFolder(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "svg", "webp":
            "Images"
        case "mov", "mp4", "m4v", "mkv", "avi", "mp3", "wav", "aiff":
            "Media"
        case "zip", "tar", "gz", "bz2", "rar", "7z":
            "Archives"
        case "swift", "js", "jsx", "ts", "tsx", "json", "toml", "yml", "yaml", "py", "go", "rs", "java", "c", "cpp", "h", "hpp":
            "Code"
        case "pdf", "doc", "docx", "txt", "md", "rtf", "pages", "xls", "xlsx", "csv", "ppt", "pptx", "key":
            "Documents"
        default:
            "Other"
        }
    }

    private static func encodeOperations(_ operations: [DesktopCleanupOperation]) -> String {
        if let data = try? JSONEncoder().encode(operations),
           let text = String(data: data, encoding: .utf8)
        {
            return text
        }
        return "[]"
    }

    private static func decodeOperations(_ text: String) throws -> [DesktopCleanupOperation] {
        guard let data = text.data(using: .utf8) else {
            throw ComputerActionError.invalidPreviewArtifact
        }
        return try JSONDecoder().decode([DesktopCleanupOperation].self, from: data)
    }
}

public struct DesktopCleanupOperation: Hashable, Sendable, Codable {
    public let sourcePath: String
    public let destinationPath: String
    public let destinationFolder: String

    public init(sourcePath: String, destinationPath: String, destinationFolder: String) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.destinationFolder = destinationFolder
    }
}

public struct DesktopCleanupUndoEntry: Hashable, Sendable, Codable {
    public let sourcePath: String
    public let movedPath: String

    public init(sourcePath: String, movedPath: String) {
        self.sourcePath = sourcePath
        self.movedPath = movedPath
    }
}

public struct DesktopCleanupUndoManifest: Hashable, Sendable, Codable {
    public let entries: [DesktopCleanupUndoEntry]
    public let createdAt: Date

    public init(entries: [DesktopCleanupUndoEntry], createdAt: Date = Date()) {
        self.entries = entries
        self.createdAt = createdAt
    }
}
