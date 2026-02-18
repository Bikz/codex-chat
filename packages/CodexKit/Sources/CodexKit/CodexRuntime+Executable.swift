import Foundation

extension CodexRuntime {
    public nonisolated static let codexInstallCommand = "brew install codex"

    public nonisolated static func launchDeviceAuthInTerminal() throws {
        guard defaultExecutableResolver() != nil else {
            throw CodexRuntimeError.binaryNotFound
        }

        try launchTerminalCommand("codex login --device-auth")
    }

    public nonisolated static func launchCodexInstallInTerminal() throws {
        guard let homebrewPath = homebrewExecutablePath() else {
            throw CodexRuntimeError.invalidResponse(
                "Homebrew was not found. Install Homebrew first, then run `\(codexInstallCommand)`."
            )
        }

        let command = "\(homebrewPath) install codex && codex --version"
        try launchTerminalCommand(command)
    }

    private nonisolated static func launchTerminalCommand(_ command: String) throws {
        let escapedCommand = applescriptEscaped(command)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to do script \"\(escapedCommand)\"",
            "-e", "tell application \"Terminal\" to activate",
        ]
        try process.run()
    }

    private nonisolated static func homebrewExecutablePath(
        fileManager: FileManager = .default
    ) -> String? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ]
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    private nonisolated static func applescriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated static func authMode(fromAccountType type: String) -> RuntimeAuthMode {
        switch type.lowercased() {
        case "apikey":
            .apiKey
        case "chatgpt":
            .chatGPT
        case "chatgptauthtokens":
            .chatGPTAuthTokens
        default:
            .unknown
        }
    }
}
