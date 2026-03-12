@testable import CodexChatShared
import Foundation

func makeTestResolvedCodexHomes(
    root: URL,
    storagePaths: CodexChatStoragePaths
) -> ResolvedCodexHomes {
    ResolvedCodexHomes(
        activeCodexHomeURL: root.appendingPathComponent(".codex-shared", isDirectory: true),
        activeAgentsHomeURL: root.appendingPathComponent(".agents-shared", isDirectory: true),
        legacyManagedCodexHomeURL: storagePaths.legacyManagedCodexHomeURL,
        legacyManagedAgentsHomeURL: storagePaths.legacyManagedAgentsHomeURL,
        source: .environmentOverride
    )
}
