import Foundation

enum AccountDisplayNamePreference {
    static let key = "account.display_name_override"

    static func normalizedName(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func resolvedDisplayName(preferredName: String, fallback: String) -> String {
        if let preferred = normalizedName(preferredName) {
            return preferred
        }
        return fallback
    }
}
