import Foundation

enum ShellPathPresentation {
    static func compactPath(_ path: String, homeDirectory: String = NSHomeDirectory()) -> String {
        let normalizedPath = normalize(path)
        guard !normalizedPath.isEmpty else { return "-" }

        let normalizedHome = normalize(homeDirectory)
        guard !normalizedHome.isEmpty else { return normalizedPath }

        if normalizedPath == normalizedHome {
            return "~"
        }

        let homePrefix = normalizedHome + "/"
        if normalizedPath.hasPrefix(homePrefix) {
            let relative = normalizedPath.dropFirst(homePrefix.count)
            return "~/" + relative
        }

        return normalizedPath
    }

    static func leafName(for path: String) -> String {
        let normalizedPath = normalize(path)
        guard !normalizedPath.isEmpty else { return "Shell" }
        guard normalizedPath != "/" else { return "/" }
        return URL(fileURLWithPath: normalizedPath).lastPathComponent
    }

    private static func normalize(_ path: String) -> String {
        var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.count > 1, normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
