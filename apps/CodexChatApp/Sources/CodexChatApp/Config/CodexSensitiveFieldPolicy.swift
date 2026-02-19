import Foundation

enum CodexSensitiveFieldPolicy {
    static func isSensitive(path: [CodexConfigPathSegment], key: String? = nil) -> Bool {
        var components = path.map(\.display)
        if let key {
            components.append(key)
        }

        let lowered = components.joined(separator: ".").lowercased()
        let sensitiveTerms = [
            "token",
            "secret",
            "password",
            "authorization",
            "bearer",
            "api_key",
            "apikey",
            "auth",
            "private_key",
            "client_secret",
        ]

        if sensitiveTerms.contains(where: { lowered.contains($0) }) {
            return true
        }

        if lowered.contains("mcp_servers"), lowered.contains("http_headers") {
            return true
        }

        if lowered.contains("experimental_bearer_token") {
            return true
        }

        return false
    }

    static func redacted(_ value: String) -> String {
        guard !value.isEmpty else {
            return ""
        }

        if value.count <= 4 {
            return String(repeating: "•", count: value.count)
        }

        let suffix = String(value.suffix(4))
        return String(repeating: "•", count: max(0, value.count - 4)) + suffix
    }
}
