import Foundation

public struct ModThemeOverride: Hashable, Codable, Sendable {
    public var accentHex: String?
    public var backgroundHex: String?
    public var panelHex: String?

    public init(accentHex: String? = nil, backgroundHex: String? = nil, panelHex: String? = nil) {
        self.accentHex = accentHex
        self.backgroundHex = backgroundHex
        self.panelHex = panelHex
    }
}
