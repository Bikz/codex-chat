import Foundation

public enum FirstPartyModTrust {
    public static let reservedNamespacePrefix = "codexchat."

    private static let officialGitHubOwner = "bikz"
    private static let officialGitHubRepository = "codexchat"
    private static let firstPartyPathComponent = "/mods/first-party/"

    public static func usesReservedNamespace(_ modID: String) -> Bool {
        modID.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix(reservedNamespacePrefix)
    }

    public static func isFirstPartyDirectoryPath(_ path: String) -> Bool {
        NSString(string: path).standardizingPath.lowercased().contains(firstPartyPathComponent)
    }

    public static func isVettedFirstPartySource(_ source: String?) -> Bool {
        let trimmed = (source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        if let fileURL = URL(string: trimmed), fileURL.isFileURL {
            return isFirstPartyDirectoryPath(fileURL.path)
        }

        if trimmed.hasPrefix("/") {
            return isFirstPartyDirectoryPath(trimmed)
        }

        return isOfficialGitHubFirstPartySource(trimmed)
    }

    public static func isVettedFirstPartyPackage(
        packageDirectoryPath: String,
        source: String?
    ) -> Bool {
        isFirstPartyDirectoryPath(packageDirectoryPath) || isVettedFirstPartySource(source)
    }

    private static func isOfficialGitHubFirstPartySource(_ source: String) -> Bool {
        guard let url = URL(string: source),
              (url.host ?? "").lowercased() == "github.com"
        else {
            return false
        }

        let components = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.removingPercentEncoding ?? String($0) }
        guard components.count >= 2 else {
            return false
        }

        let owner = components[0].lowercased()
        let repository = stripGitSuffix(components[1]).lowercased()
        guard owner == officialGitHubOwner, repository == officialGitHubRepository else {
            return false
        }

        let decodedPath = (url.path.removingPercentEncoding ?? url.path).lowercased()
        return decodedPath.contains(firstPartyPathComponent)
    }

    private static func stripGitSuffix(_ repository: String) -> String {
        if repository.lowercased().hasSuffix(".git") {
            return String(repository.dropLast(4))
        }
        return repository
    }
}
