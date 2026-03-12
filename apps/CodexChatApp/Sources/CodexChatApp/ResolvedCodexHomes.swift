import Foundation

struct ResolvedCodexHomes: Hashable, Sendable {
    enum Source: String, Hashable, Sendable, Codable {
        case environmentOverride
        case defaultUserHome

        var displayLabel: String {
            switch self {
            case .environmentOverride:
                "Environment Override"
            case .defaultUserHome:
                "Default User Home"
            }
        }
    }

    let activeCodexHomeURL: URL
    let activeAgentsHomeURL: URL
    let legacyManagedCodexHomeURL: URL
    let legacyManagedAgentsHomeURL: URL
    let source: Source

    var activeCodexConfigURL: URL {
        activeCodexHomeURL.appendingPathComponent("config.toml", isDirectory: false)
    }

    var activeGlobalSkillsURL: URL {
        activeAgentsHomeURL.appendingPathComponent("skills", isDirectory: true)
    }

    static func current(
        storagePaths: CodexChatStoragePaths = .current(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> ResolvedCodexHomes {
        let source: Source
        let activeCodexHomeURL: URL

        if let override = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            source = .environmentOverride
            activeCodexHomeURL = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        } else {
            source = .defaultUserHome
            activeCodexHomeURL = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .standardizedFileURL
        }

        let activeAgentsHomeURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents", isDirectory: true)
            .standardizedFileURL

        return ResolvedCodexHomes(
            activeCodexHomeURL: activeCodexHomeURL,
            activeAgentsHomeURL: activeAgentsHomeURL,
            legacyManagedCodexHomeURL: storagePaths.legacyManagedCodexHomeURL,
            legacyManagedAgentsHomeURL: storagePaths.legacyManagedAgentsHomeURL,
            source: source
        )
    }
}
