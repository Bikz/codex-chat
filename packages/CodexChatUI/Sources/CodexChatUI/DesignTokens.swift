import CodexMods
import SwiftUI

public struct DesignTokens: Hashable, Sendable {
    public struct Typography: Hashable, Sendable {
        public var titleSize: CGFloat
        public var bodySize: CGFloat
        public var captionSize: CGFloat

        public init(titleSize: CGFloat = 21, bodySize: CGFloat = 14, captionSize: CGFloat = 12) {
            self.titleSize = titleSize
            self.bodySize = bodySize
            self.captionSize = captionSize
        }
    }

    public struct Spacing: Hashable, Sendable {
        public var xSmall: CGFloat
        public var small: CGFloat
        public var medium: CGFloat
        public var large: CGFloat

        public init(xSmall: CGFloat = 6, small: CGFloat = 10, medium: CGFloat = 16, large: CGFloat = 24) {
            self.xSmall = xSmall
            self.small = small
            self.medium = medium
            self.large = large
        }
    }

    public struct Radius: Hashable, Sendable {
        public var small: CGFloat
        public var medium: CGFloat
        public var large: CGFloat

        public init(small: CGFloat = 8, medium: CGFloat = 14, large: CGFloat = 20) {
            self.small = small
            self.medium = medium
            self.large = large
        }
    }

    public struct Palette: Hashable, Sendable {
        public var accentHex: String
        public var backgroundHex: String
        public var panelHex: String

        public init(
            accentHex: String = "#2E7D32",
            backgroundHex: String = "#F7F8F7",
            panelHex: String = "#FFFFFF"
        ) {
            self.accentHex = accentHex
            self.backgroundHex = backgroundHex
            self.panelHex = panelHex
        }
    }

    public var typography: Typography
    public var spacing: Spacing
    public var radius: Radius
    public var palette: Palette

    public init(
        typography: Typography = Typography(),
        spacing: Spacing = Spacing(),
        radius: Radius = Radius(),
        palette: Palette = Palette()
    ) {
        self.typography = typography
        self.spacing = spacing
        self.radius = radius
        self.palette = palette
    }

    public static let `default` = DesignTokens()

    public func applying(override: ModThemeOverride) -> DesignTokens {
        var copy = self
        if let accentHex = override.accentHex {
            copy.palette.accentHex = accentHex
        }
        if let backgroundHex = override.backgroundHex {
            copy.palette.backgroundHex = backgroundHex
        }
        if let panelHex = override.panelHex {
            copy.palette.panelHex = panelHex
        }
        return copy
    }
}

@MainActor
public final class ThemeProvider: ObservableObject {
    @Published public private(set) var tokens: DesignTokens
    private let baseline: DesignTokens

    public init(tokens: DesignTokens = .default) {
        self.tokens = tokens
        self.baseline = tokens
    }

    public func apply(override: ModThemeOverride) {
        tokens = baseline.applying(override: override)
    }

    public func reset() {
        tokens = baseline
    }
}

private struct DesignTokensKey: EnvironmentKey {
    static let defaultValue = DesignTokens.default
}

public extension EnvironmentValues {
    var designTokens: DesignTokens {
        get { self[DesignTokensKey.self] }
        set { self[DesignTokensKey.self] = newValue }
    }
}

public extension View {
    func designTokens(_ tokens: DesignTokens) -> some View {
        environment(\.designTokens, tokens)
    }
}

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
