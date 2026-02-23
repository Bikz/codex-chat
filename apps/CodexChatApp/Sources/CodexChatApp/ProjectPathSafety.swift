import Foundation

enum ProjectPathSafety {
    static func destinationURL(for relativePath: String, projectPath: String) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: projectPath, isDirectory: true).standardizedFileURL
        let destinationURL = URL(fileURLWithPath: trimmed, relativeTo: rootURL).standardizedFileURL

        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"
        guard destinationURL.path.hasPrefix(rootPrefix) else {
            return nil
        }

        return destinationURL
    }
}
