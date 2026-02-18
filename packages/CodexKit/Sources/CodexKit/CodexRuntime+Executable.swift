import Foundation

extension CodexRuntime {
    public nonisolated static func launchDeviceAuthInTerminal() throws {
        guard defaultExecutableResolver() != nil else {
            throw CodexRuntimeError.binaryNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to do script \"codex login --device-auth\"",
            "-e", "tell application \"Terminal\" to activate",
        ]
        try process.run()
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
