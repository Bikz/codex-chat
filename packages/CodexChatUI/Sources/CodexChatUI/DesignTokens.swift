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

        public init(xSmall: CGFloat = 4, small: CGFloat = 8, medium: CGFloat = 16, large: CGFloat = 24) {
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

        public init(small: CGFloat = 6, medium: CGFloat = 14, large: CGFloat = 22) {
            self.small = small
            self.medium = medium
            self.large = large
        }
    }

    public struct Palette: Hashable, Sendable {
        public var accentHex: String
        public var backgroundHex: String
        public var panelHex: String
        public var sidebarHex: String

        public init(
            accentHex: String = "#10A37F",
            backgroundHex: String = "#F9F9F9",
            panelHex: String = "#FFFFFF",
            sidebarHex: String = "#F5F5F5"
        ) {
            self.accentHex = accentHex
            self.backgroundHex = backgroundHex
            self.panelHex = panelHex
            self.sidebarHex = sidebarHex
        }
    }

    public var typography: Typography
    public var spacing: Spacing
    public var radius: Radius
    public var palette: Palette
    public var materials: Materials
    public var bubbles: Bubbles
    public var iconography: Iconography

    public init(
        typography: Typography = Typography(),
        spacing: Spacing = Spacing(),
        radius: Radius = Radius(),
        palette: Palette = Palette(),
        materials: Materials = Materials(),
        bubbles: Bubbles = Bubbles(),
        iconography: Iconography = Iconography()
    ) {
        self.typography = typography
        self.spacing = spacing
        self.radius = radius
        self.palette = palette
        self.materials = materials
        self.bubbles = bubbles
        self.iconography = iconography
    }

    public static let systemLight = DesignTokens()
    public static let systemDark = DesignTokens(
        palette: Palette(accentHex: "#10A37F", backgroundHex: "#000000", panelHex: "#121212", sidebarHex: "#0A0A0A"),
        bubbles: Bubbles(style: .glass, userBackgroundHex: "#10A37F", assistantBackgroundHex: "#1C1C1E")
    )
    public static let `default` = systemLight

    public func applying(override: ModThemeOverride) -> DesignTokens {
        var copy = self
        if let titleSize = override.typography?.titleSize {
            copy.typography.titleSize = CGFloat(titleSize)
        }
        if let bodySize = override.typography?.bodySize {
            copy.typography.bodySize = CGFloat(bodySize)
        }
        if let captionSize = override.typography?.captionSize {
            copy.typography.captionSize = CGFloat(captionSize)
        }

        if let xSmall = override.spacing?.xSmall {
            copy.spacing.xSmall = CGFloat(xSmall)
        }
        if let small = override.spacing?.small {
            copy.spacing.small = CGFloat(small)
        }
        if let medium = override.spacing?.medium {
            copy.spacing.medium = CGFloat(medium)
        }
        if let large = override.spacing?.large {
            copy.spacing.large = CGFloat(large)
        }

        if let small = override.radius?.small {
            copy.radius.small = CGFloat(small)
        }
        if let medium = override.radius?.medium {
            copy.radius.medium = CGFloat(medium)
        }
        if let large = override.radius?.large {
            copy.radius.large = CGFloat(large)
        }

        if let accentHex = override.resolvedPaletteAccentHex {
            copy.palette.accentHex = accentHex
        }
        if let backgroundHex = override.resolvedPaletteBackgroundHex {
            copy.palette.backgroundHex = backgroundHex
        }
        if let panelHex = override.resolvedPalettePanelHex {
            copy.palette.panelHex = panelHex
        }
        // sidebarHex is not overridden by mods — intentional

        if let panel = override.materials?.panelMaterial,
           let material = DesignMaterial(rawValue: panel)
        {
            copy.materials.panelMaterial = material
        }
        if let card = override.materials?.cardMaterial,
           let material = DesignMaterial(rawValue: card)
        {
            copy.materials.cardMaterial = material
        }

        if let style = override.bubbles?.style,
           let bubbleStyle = BubbleStyle(rawValue: style)
        {
            copy.bubbles.style = bubbleStyle
        }
        if let userHex = override.bubbles?.userBackgroundHex {
            copy.bubbles.userBackgroundHex = userHex
        }
        if let assistantHex = override.bubbles?.assistantBackgroundHex {
            copy.bubbles.assistantBackgroundHex = assistantHex
        }

        if let iconStyle = override.iconography?.style,
           let resolved = Iconography.Style(rawValue: iconStyle)
        {
            copy.iconography.style = resolved
        }

        return copy
    }
}

public extension DesignTokens {
    enum DesignMaterial: String, CaseIterable, Hashable, Sendable, Codable {
        case ultraThin
        case thin
        case regular
        case thick
        case ultraThick

        public var material: Material {
            switch self {
            case .ultraThin:
                .ultraThinMaterial
            case .thin:
                .thinMaterial
            case .regular:
                .regularMaterial
            case .thick:
                .thickMaterial
            case .ultraThick:
                .ultraThickMaterial
            }
        }
    }

    struct Materials: Hashable, Sendable {
        public var panelMaterial: DesignMaterial
        public var cardMaterial: DesignMaterial

        public init(panelMaterial: DesignMaterial = .thin, cardMaterial: DesignMaterial = .regular) {
            self.panelMaterial = panelMaterial
            self.cardMaterial = cardMaterial
        }
    }

    enum BubbleStyle: String, CaseIterable, Hashable, Sendable, Codable {
        case plain
        case glass
        case solid
    }

    struct Bubbles: Hashable, Sendable {
        public var style: BubbleStyle
        public var userBackgroundHex: String
        public var assistantBackgroundHex: String

        public init(
            style: BubbleStyle = .glass,
            userBackgroundHex: String = "#10A37F",
            assistantBackgroundHex: String = "#FFFFFF"
        ) {
            self.style = style
            self.userBackgroundHex = userBackgroundHex
            self.assistantBackgroundHex = assistantBackgroundHex
        }
    }

    struct Iconography: Hashable, Sendable {
        public enum Style: String, CaseIterable, Hashable, Sendable, Codable {
            case sfSymbols = "sf-symbols"
        }

        public var style: Style

        public init(style: Style = .sfSymbols) {
            self.style = style
        }
    }
}

@MainActor
public final class ThemeProvider: ObservableObject {
    @Published public private(set) var tokens: DesignTokens
    private let baseline: DesignTokens

    public init(tokens: DesignTokens = .default) {
        self.tokens = tokens
        baseline = tokens
    }

    public func apply(override: ModThemeOverride) {
        tokens = baseline.applying(override: override)
    }

    public func reset() {
        tokens = baseline
    }
}

public extension EnvironmentValues {
    @Entry var designTokens: DesignTokens = .default
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

        let alpha, red, green, blue: UInt64
        switch hex.count {
        case 3:
            (alpha, red, green, blue) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (alpha, red, green, blue) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (alpha, red, green, blue) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (alpha, red, green, blue) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}
