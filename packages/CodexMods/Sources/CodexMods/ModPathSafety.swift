import Foundation

enum ModPathSafety {
    static func normalizedSafeRelativePath(_ rawPath: String?) -> String? {
        let trimmed = (rawPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("/") else { return nil }

        let components = NSString(string: trimmed).pathComponents
        if components.contains("..") {
            return nil
        }
        return trimmed
    }

    static func isWithinRoot(candidateURL: URL, rootURL: URL) -> Bool {
        let normalizedRoot = rootURL.standardizedFileURL
        let normalizedCandidate = candidateURL.standardizedFileURL
        let rootPrefix = normalizedRoot.path.hasSuffix("/")
            ? normalizedRoot.path
            : "\(normalizedRoot.path)/"
        return normalizedCandidate.path == normalizedRoot.path
            || normalizedCandidate.path.hasPrefix(rootPrefix)
    }
}
