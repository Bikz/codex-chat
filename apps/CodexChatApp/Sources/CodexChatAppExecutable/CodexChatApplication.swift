import CodexChatShared
import SwiftUI

/// Deprecated migration-only fallback.
/// Canonical GUI entrypoint lives in apps/CodexChatHost.
@available(*, deprecated, message: "Use CodexChatHost for GUI runs. This fallback will be removed after migration.")
@main
struct CodexChatApplication: App {
    var body: some Scene {
        CodexChatDesktopScene()
    }
}
