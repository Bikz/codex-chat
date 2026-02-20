import CodexChatCore
import Foundation

public final class FilesReadAction: ComputerActionProvider {
    private enum Constants {
        static let maxListingEntries = 500
    }

    public init() {}

    public let actionID = "files.read"
    public let displayName = "Files Read"
    public let safetyLevel: ComputerActionSafetyLevel = .readOnly
    public let requiresConfirmation = false

    public func preview(request: ComputerActionRequest) async throws -> ComputerActionPreviewArtifact {
        let rawPath = request.arguments["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawPath.isEmpty else {
            throw ComputerActionError.invalidArguments("Provide a `path` argument for files.read.")
        }

        let canonicalURL = try canonicalizedExistingURL(for: rawPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonicalURL.path, isDirectory: &isDirectory) else {
            throw ComputerActionError.invalidArguments("Path does not exist: \(canonicalURL.path)")
        }

        if isDirectory.boolValue {
            return try previewDirectoryRead(
                request: request,
                canonicalURL: canonicalURL
            )
        }
        return try previewFileMetadataRead(
            request: request,
            canonicalURL: canonicalURL
        )
    }

    public func execute(
        request: ComputerActionRequest,
        preview: ComputerActionPreviewArtifact
    ) async throws -> ComputerActionExecutionResult {
        try validate(preview: preview, request: request)
        let mode = preview.data["mode"] ?? "unknown"

        return ComputerActionExecutionResult(
            actionID: actionID,
            runContextID: request.runContextID,
            summary: preview.summary,
            detailsMarkdown: preview.detailsMarkdown,
            metadata: [
                "mode": mode,
                "path": preview.data["path"] ?? "",
            ]
        )
    }

    private func previewFileMetadataRead(
        request: ComputerActionRequest,
        canonicalURL: URL
    ) throws -> ComputerActionPreviewArtifact {
        let attributes = try FileManager.default.attributesOfItem(atPath: canonicalURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = (attributes[.modificationDate] as? Date) ?? Date()
        let formatter = ISO8601DateFormatter()
        let modifiedText = formatter.string(from: modifiedAt)

        let details = """
        Path: `\(canonicalURL.path)`
        Type: `file`
        Size: `\(byteCount)` bytes
        Modified: `\(modifiedText)`
        """

        return ComputerActionPreviewArtifact(
            actionID: actionID,
            runContextID: request.runContextID,
            title: "File Metadata Preview",
            summary: "Read metadata for file `\(canonicalURL.lastPathComponent)`.",
            detailsMarkdown: details,
            data: [
                "path": canonicalURL.path,
                "mode": "file",
                "sizeBytes": String(byteCount),
                "modifiedAt": modifiedText,
            ]
        )
    }

    private func previewDirectoryRead(
        request: ComputerActionRequest,
        canonicalURL: URL
    ) throws -> ComputerActionPreviewArtifact {
        let includeHidden = parseBool(request.arguments["includeHidden"])
        let maxEntries = min(
            Constants.maxListingEntries,
            max(1, Int(request.arguments["maxEntries"] ?? "200") ?? 200)
        )

        let childNames = try FileManager.default.contentsOfDirectory(atPath: canonicalURL.path)
            .filter { includeHidden || !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .prefix(maxEntries)

        let rows = try childNames.map { childName -> String in
            let childURL = canonicalURL.appendingPathComponent(childName, isDirectory: false)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: childURL.path, isDirectory: &isDirectory)
            guard exists else {
                return "- `\(childName)` _(missing)_"
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: childURL.path)
            if isDirectory.boolValue {
                return "- `\(childName)/` (directory)"
            }
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            return "- `\(childName)` (\(byteCount) bytes)"
        }

        let details = if rows.isEmpty {
            "Path: `\(canonicalURL.path)`\n\n_No entries found._"
        } else {
            """
            Path: `\(canonicalURL.path)`
            Type: `directory`
            Entries shown: `\(rows.count)`

            \(rows.joined(separator: "\n"))
            """
        }

        return ComputerActionPreviewArtifact(
            actionID: actionID,
            runContextID: request.runContextID,
            title: "Directory Listing Preview",
            summary: "Listed \(rows.count) entr\(rows.count == 1 ? "y" : "ies") in `\(canonicalURL.lastPathComponent)`.",
            detailsMarkdown: details,
            data: [
                "path": canonicalURL.path,
                "mode": "directory",
                "entryCount": String(rows.count),
            ]
        )
    }

    private func canonicalizedExistingURL(for rawPath: String) throws -> URL {
        let normalized = URL(fileURLWithPath: rawPath, isDirectory: false).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory) else {
            throw ComputerActionError.invalidArguments("Path does not exist: \(normalized)")
        }
        return URL(fileURLWithPath: normalized, isDirectory: isDirectory.boolValue).resolvingSymlinksInPath()
    }

    private func parseBool(_ value: String?) -> Bool {
        guard let value else { return false }
        return switch value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "1", "true", "yes", "y", "on":
            true
        default:
            false
        }
    }
}

public final class FilesMoveAction: ComputerActionProvider {
    private enum Constants {
        static let protectedPathPrefixes = [
            "/System",
            "/Library",
            "/Applications",
            "/usr",
            "/bin",
            "/sbin",
            "/private/var/db",
        ]
    }

    private struct MovePlan: Codable, Hashable {
        let sourcePath: String
        let destinationPath: String
        let finalDestinationPath: String
        let collisionPolicy: String
        let sourceIsDirectory: Bool
    }

    public init() {}

    public let actionID = "files.move"
    public let displayName = "Files Move"
    public let safetyLevel: ComputerActionSafetyLevel = .destructive
    public let requiresConfirmation = true

    public func preview(request: ComputerActionRequest) async throws -> ComputerActionPreviewArtifact {
        let plan = try buildMovePlan(arguments: request.arguments)
        let details = """
        Source: `\(plan.sourcePath)`
        Destination: `\(plan.destinationPath)`
        Final destination: `\(plan.finalDestinationPath)`
        Collision policy: `\(plan.collisionPolicy)`

        Risk warning: **This action moves data on disk. Confirm the source and destination before running.**
        """

        return ComputerActionPreviewArtifact(
            actionID: actionID,
            runContextID: request.runContextID,
            title: "Move Preview",
            summary: "Ready to move `\(URL(fileURLWithPath: plan.sourcePath).lastPathComponent)`.",
            detailsMarkdown: details,
            data: ["movePlan": encodeMovePlan(plan)]
        )
    }

    public func execute(
        request: ComputerActionRequest,
        preview: ComputerActionPreviewArtifact
    ) async throws -> ComputerActionExecutionResult {
        try validate(preview: preview, request: request)
        guard let encodedPlan = preview.data["movePlan"],
              let previewPlan = decodeMovePlan(encodedPlan)
        else {
            throw ComputerActionError.invalidPreviewArtifact
        }

        let currentPlan = try buildMovePlan(arguments: request.arguments)
        guard currentPlan == previewPlan else {
            throw ComputerActionError.invalidArguments(
                "Move request changed after preview. Generate a fresh preview before moving files."
            )
        }

        if FileManager.default.fileExists(atPath: currentPlan.finalDestinationPath) {
            throw ComputerActionError.executionFailed(
                "Destination already exists: \(currentPlan.finalDestinationPath). Generate a new preview."
            )
        }

        let sourceURL = URL(fileURLWithPath: currentPlan.sourcePath, isDirectory: currentPlan.sourceIsDirectory)
        let destinationURL = URL(fileURLWithPath: currentPlan.finalDestinationPath, isDirectory: currentPlan.sourceIsDirectory)

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            throw ComputerActionError.executionFailed("Failed to move file: \(error.localizedDescription)")
        }

        let manifestPath = try writeRollbackManifest(
            sourcePath: currentPlan.sourcePath,
            destinationPath: currentPlan.finalDestinationPath,
            request: request
        )

        return ComputerActionExecutionResult(
            actionID: actionID,
            runContextID: request.runContextID,
            summary: "Moved `\(sourceURL.lastPathComponent)` to `\(destinationURL.path)`.",
            detailsMarkdown: """
            Move completed.

            - From: `\(currentPlan.sourcePath)`
            - To: `\(currentPlan.finalDestinationPath)`
            - Rollback manifest: `\(manifestPath)`
            """,
            metadata: [
                "movedFrom": currentPlan.sourcePath,
                "movedTo": currentPlan.finalDestinationPath,
                "rollbackManifestPath": manifestPath,
            ]
        )
    }

    private func buildMovePlan(arguments: [String: String]) throws -> MovePlan {
        let sourceRaw = arguments["sourcePath"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let destinationRaw = arguments["destinationPath"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !sourceRaw.isEmpty else {
            throw ComputerActionError.invalidArguments("Provide `sourcePath` for files.move.")
        }
        guard !destinationRaw.isEmpty else {
            throw ComputerActionError.invalidArguments("Provide `destinationPath` for files.move.")
        }

        let sourceURL = try canonicalizedExistingURL(for: sourceRaw)
        var sourceIsDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &sourceIsDirectory) else {
            throw ComputerActionError.invalidArguments("Source path does not exist: \(sourceURL.path)")
        }

        let destinationURL = canonicalizeDestinationURL(rawPath: destinationRaw)
        try guardNotProtectedPath(sourceURL.path)
        try guardNotProtectedPath(destinationURL.path)

        guard sourceURL.path != destinationURL.path else {
            throw ComputerActionError.invalidArguments("Source and destination cannot be the same path.")
        }

        if sourceIsDirectory.boolValue,
           destinationURL.path.hasPrefix(sourceURL.path + "/")
        {
            throw ComputerActionError.invalidArguments("Cannot move a directory into itself.")
        }

        let collisionPolicy = normalizedCollisionPolicy(arguments["collisionPolicy"])
        let finalDestinationURL = try resolveFinalDestination(
            sourceURL: sourceURL,
            sourceIsDirectory: sourceIsDirectory.boolValue,
            destinationURL: destinationURL,
            collisionPolicy: collisionPolicy
        )

        return MovePlan(
            sourcePath: sourceURL.path,
            destinationPath: destinationURL.path,
            finalDestinationPath: finalDestinationURL.path,
            collisionPolicy: collisionPolicy,
            sourceIsDirectory: sourceIsDirectory.boolValue
        )
    }

    private func resolveFinalDestination(
        sourceURL: URL,
        sourceIsDirectory: Bool,
        destinationURL: URL,
        collisionPolicy: String
    ) throws -> URL {
        var destinationIsDirectory = ObjCBool(false)
        let destinationExists = FileManager.default.fileExists(atPath: destinationURL.path, isDirectory: &destinationIsDirectory)

        let baseDestination: URL = if destinationExists, destinationIsDirectory.boolValue {
            destinationURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: sourceIsDirectory)
        } else {
            destinationURL
        }

        if !FileManager.default.fileExists(atPath: baseDestination.path) {
            return baseDestination
        }

        switch collisionPolicy {
        case "rename":
            return uniqueDestinationURL(base: baseDestination, isDirectory: sourceIsDirectory)
        case "error":
            throw ComputerActionError.invalidArguments("Destination already exists: \(baseDestination.path)")
        default:
            throw ComputerActionError.invalidArguments("Unsupported collisionPolicy: \(collisionPolicy)")
        }
    }

    private func uniqueDestinationURL(base: URL, isDirectory _: Bool) -> URL {
        let fileExtension = base.pathExtension
        let baseName = fileExtension.isEmpty ? base.lastPathComponent : String(base.lastPathComponent.dropLast(fileExtension.count + 1))
        let directory = base.deletingLastPathComponent()

        for index in 2 ... 10000 {
            let suffixedName = if fileExtension.isEmpty {
                "\(baseName) (\(index))"
            } else {
                "\(baseName) (\(index)).\(fileExtension)"
            }
            let candidate = directory.appendingPathComponent(suffixedName, isDirectory: false)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent(UUID().uuidString, isDirectory: false)
    }

    private func normalizedCollisionPolicy(_ rawValue: String?) -> String {
        let normalized = rawValue?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? "error"
        return normalized.isEmpty ? "error" : normalized
    }

    private func canonicalizedExistingURL(for rawPath: String) throws -> URL {
        let normalized = URL(fileURLWithPath: rawPath, isDirectory: false).standardizedFileURL.path
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory) else {
            throw ComputerActionError.invalidArguments("Path does not exist: \(normalized)")
        }
        return URL(fileURLWithPath: normalized, isDirectory: isDirectory.boolValue).resolvingSymlinksInPath()
    }

    private func canonicalizeDestinationURL(rawPath: String) -> URL {
        let rawURL = URL(fileURLWithPath: rawPath, isDirectory: false).standardizedFileURL
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: rawURL.path, isDirectory: &isDirectory) {
            return URL(fileURLWithPath: rawURL.path, isDirectory: isDirectory.boolValue).resolvingSymlinksInPath()
        }

        let parent = rawURL.deletingLastPathComponent().resolvingSymlinksInPath()
        return parent.appendingPathComponent(rawURL.lastPathComponent, isDirectory: false)
    }

    private func guardNotProtectedPath(_ path: String) throws {
        for protectedPrefix in Constants.protectedPathPrefixes {
            if path == protectedPrefix || path.hasPrefix(protectedPrefix + "/") {
                throw ComputerActionError.unsupported("Protected system path is not allowed: \(path)")
            }
        }
    }

    private func encodeMovePlan(_ plan: MovePlan) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(plan),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    private func decodeMovePlan(_ text: String) -> MovePlan? {
        guard let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(MovePlan.self, from: data)
    }

    private func writeRollbackManifest(
        sourcePath: String,
        destinationPath: String,
        request: ComputerActionRequest
    ) throws -> String {
        guard let artifactDirectoryPath = request.artifactDirectoryPath,
              !artifactDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return ""
        }

        let directoryURL = URL(fileURLWithPath: artifactDirectoryPath, isDirectory: true)
            .appendingPathComponent("files-move-manifests", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let manifestURL = directoryURL.appendingPathComponent(
            "move-\(request.runContextID)-\(UUID().uuidString).json",
            isDirectory: false
        )

        let manifest: [String: String] = [
            "movedFrom": sourcePath,
            "movedTo": destinationPath,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifestURL, options: .atomic)
        return manifestURL.path
    }
}
