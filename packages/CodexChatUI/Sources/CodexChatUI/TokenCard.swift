import SwiftUI

public enum TokenCardStyle: Hashable, Sendable {
    case panel
    case card
}

private struct TokenCardModifier: ViewModifier {
    let style: TokenCardStyle
    let radius: CGFloat?
    let strokeOpacity: Double
    let shadowRadius: CGFloat

    @Environment(\.designTokens) private var tokens

    func body(content: Content) -> some View {
        let resolvedRadius = radius ?? tokens.radius.medium
        let shape = RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
        let material = switch style {
        case .panel:
            tokens.materials.panelMaterial.material
        case .card:
            tokens.materials.cardMaterial.material
        }

        content
            .background(material, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(strokeOpacity)))
            .clipShape(shape)
            .shadow(color: .black.opacity(shadowRadius > 0 ? 0.04 : 0), radius: shadowRadius, y: shadowRadius > 0 ? 2 : 0)
    }
}

public extension View {
    func tokenCard(
        style: TokenCardStyle = .card,
        radius: CGFloat? = nil,
        strokeOpacity: Double = 0.08,
        shadowRadius: CGFloat = 0
    ) -> some View {
        modifier(TokenCardModifier(style: style, radius: radius, strokeOpacity: strokeOpacity, shadowRadius: shadowRadius))
    }
}
