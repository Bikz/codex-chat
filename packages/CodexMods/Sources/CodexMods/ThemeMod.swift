import Foundation

public struct ModThemeOverride: Hashable, Codable, Sendable {
    public struct Typography: Hashable, Codable, Sendable {
        public var titleSize: Double?
        public var bodySize: Double?
        public var captionSize: Double?

        public init(titleSize: Double? = nil, bodySize: Double? = nil, captionSize: Double? = nil) {
            self.titleSize = titleSize
            self.bodySize = bodySize
            self.captionSize = captionSize
        }
    }

    public struct Spacing: Hashable, Codable, Sendable {
        public var xSmall: Double?
        public var small: Double?
        public var medium: Double?
        public var large: Double?

        public init(xSmall: Double? = nil, small: Double? = nil, medium: Double? = nil, large: Double? = nil) {
            self.xSmall = xSmall
            self.small = small
            self.medium = medium
            self.large = large
        }
    }

    public struct Radius: Hashable, Codable, Sendable {
        public var small: Double?
        public var medium: Double?
        public var large: Double?

        public init(small: Double? = nil, medium: Double? = nil, large: Double? = nil) {
            self.small = small
            self.medium = medium
            self.large = large
        }
    }

    public struct Palette: Hashable, Codable, Sendable {
        public var accentHex: String?
        public var backgroundHex: String?
        public var panelHex: String?

        public init(accentHex: String? = nil, backgroundHex: String? = nil, panelHex: String? = nil) {
            self.accentHex = accentHex
            self.backgroundHex = backgroundHex
            self.panelHex = panelHex
        }
    }

    public struct Materials: Hashable, Codable, Sendable {
        public var panelMaterial: String?
        public var cardMaterial: String?

        public init(panelMaterial: String? = nil, cardMaterial: String? = nil) {
            self.panelMaterial = panelMaterial
            self.cardMaterial = cardMaterial
        }
    }

    public struct Bubbles: Hashable, Codable, Sendable {
        public var style: String?
        public var userBackgroundHex: String?
        public var assistantBackgroundHex: String?

        public init(style: String? = nil, userBackgroundHex: String? = nil, assistantBackgroundHex: String? = nil) {
            self.style = style
            self.userBackgroundHex = userBackgroundHex
            self.assistantBackgroundHex = assistantBackgroundHex
        }
    }

    public struct Iconography: Hashable, Codable, Sendable {
        public var style: String?

        public init(style: String? = nil) {
            self.style = style
        }
    }

    // Legacy shorthand (still supported).
    public var accentHex: String?
    public var backgroundHex: String?
    public var panelHex: String?

    public var typography: Typography?
    public var spacing: Spacing?
    public var radius: Radius?
    public var palette: Palette?
    public var materials: Materials?
    public var bubbles: Bubbles?
    public var iconography: Iconography?

    public init(
        accentHex: String? = nil,
        backgroundHex: String? = nil,
        panelHex: String? = nil,
        typography: Typography? = nil,
        spacing: Spacing? = nil,
        radius: Radius? = nil,
        palette: Palette? = nil,
        materials: Materials? = nil,
        bubbles: Bubbles? = nil,
        iconography: Iconography? = nil
    ) {
        self.accentHex = accentHex
        self.backgroundHex = backgroundHex
        self.panelHex = panelHex
        self.typography = typography
        self.spacing = spacing
        self.radius = radius
        self.palette = palette
        self.materials = materials
        self.bubbles = bubbles
        self.iconography = iconography
    }

    public func merged(with other: ModThemeOverride) -> ModThemeOverride {
        ModThemeOverride(
            accentHex: other.accentHex ?? accentHex,
            backgroundHex: other.backgroundHex ?? backgroundHex,
            panelHex: other.panelHex ?? panelHex,
            typography: merged(typography, other.typography) { base, overlay in
                Typography(
                    titleSize: overlay.titleSize ?? base.titleSize,
                    bodySize: overlay.bodySize ?? base.bodySize,
                    captionSize: overlay.captionSize ?? base.captionSize
                )
            },
            spacing: merged(spacing, other.spacing) { base, overlay in
                Spacing(
                    xSmall: overlay.xSmall ?? base.xSmall,
                    small: overlay.small ?? base.small,
                    medium: overlay.medium ?? base.medium,
                    large: overlay.large ?? base.large
                )
            },
            radius: merged(radius, other.radius) { base, overlay in
                Radius(
                    small: overlay.small ?? base.small,
                    medium: overlay.medium ?? base.medium,
                    large: overlay.large ?? base.large
                )
            },
            palette: merged(palette, other.palette) { base, overlay in
                Palette(
                    accentHex: overlay.accentHex ?? base.accentHex,
                    backgroundHex: overlay.backgroundHex ?? base.backgroundHex,
                    panelHex: overlay.panelHex ?? base.panelHex
                )
            },
            materials: merged(materials, other.materials) { base, overlay in
                Materials(
                    panelMaterial: overlay.panelMaterial ?? base.panelMaterial,
                    cardMaterial: overlay.cardMaterial ?? base.cardMaterial
                )
            },
            bubbles: merged(bubbles, other.bubbles) { base, overlay in
                Bubbles(
                    style: overlay.style ?? base.style,
                    userBackgroundHex: overlay.userBackgroundHex ?? base.userBackgroundHex,
                    assistantBackgroundHex: overlay.assistantBackgroundHex ?? base.assistantBackgroundHex
                )
            },
            iconography: merged(iconography, other.iconography) { base, overlay in
                Iconography(style: overlay.style ?? base.style)
            }
        )
    }

    public func withoutColorOverrides() -> ModThemeOverride {
        ModThemeOverride(
            typography: typography,
            spacing: spacing,
            radius: radius,
            materials: materials,
            bubbles: bubbles.map {
                Bubbles(
                    style: $0.style,
                    userBackgroundHex: nil,
                    assistantBackgroundHex: nil
                )
            },
            iconography: iconography
        )
    }

    public func resolvedDarkOverride(using darkTheme: ModThemeOverride) -> ModThemeOverride {
        withoutColorOverrides().merged(with: darkTheme)
    }

    public var resolvedPaletteAccentHex: String? {
        palette?.accentHex ?? accentHex
    }

    public var resolvedPaletteBackgroundHex: String? {
        palette?.backgroundHex ?? backgroundHex
    }

    public var resolvedPalettePanelHex: String? {
        palette?.panelHex ?? panelHex
    }

    private func merged<T>(
        _ base: T?,
        _ overlay: T?,
        using merge: (T, T) -> T
    ) -> T? {
        switch (base, overlay) {
        case (nil, nil):
            nil
        case (nil, let overlay?):
            overlay
        case (let base?, nil):
            base
        case let (base?, overlay?):
            merge(base, overlay)
        }
    }
}
