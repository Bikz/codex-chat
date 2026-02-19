import CodexChatUI
import SwiftUI

struct SidebarRowButtonStyle: ButtonStyle {
    let isActive: Bool
    let cornerRadius: CGFloat
    let isHoveredOverride: Bool?

    init(
        isActive: Bool = false,
        cornerRadius: CGFloat = 8,
        isHovered: Bool? = nil
    ) {
        self.isActive = isActive
        self.cornerRadius = cornerRadius
        isHoveredOverride = isHovered
    }

    @State private var isHoveredInternal = false
    @Environment(\.designTokens) private var tokens

    func makeBody(configuration: Configuration) -> some View {
        let isHovered = isHoveredOverride ?? isHoveredInternal

        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundFill(isPressed: configuration.isPressed, isHovered: isHovered))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.988 : 1.0)
            .animation(.easeInOut(duration: tokens.motion.pressDuration), value: configuration.isPressed)
            .onHover { hovering in
                guard isHoveredOverride == nil else { return }
                withAnimation(.easeInOut(duration: tokens.motion.hoverDuration)) {
                    isHoveredInternal = hovering
                }
            }
    }

    @ViewBuilder
    private func backgroundFill(isPressed: Bool, isHovered: Bool) -> some View {
        if isActive {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(tokens.surfaces.activeOpacity))
        } else if isPressed {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(tokens.surfaces.activeOpacity * 1.05))
        } else if isHovered {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(tokens.surfaces.raisedOpacity))
        } else {
            Color.clear
        }
    }
}

struct UserInitialCircle: View {
    let name: String
    let size: CGFloat

    init(_ name: String, size: CGFloat = 24) {
        self.name = name
        self.size = size
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "?"
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(Color.primary.opacity(0.48))
            )
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
    }
}

struct SidebarSectionHeader: View {
    let title: String
    let font: Font
    let actionSystemImage: String?
    let actionAccessibilityLabel: String?
    let trailingAlignmentWidth: CGFloat?
    let trailingPadding: CGFloat
    let action: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.designTokens) private var tokens
    @State private var isActionHovered = false

    init(
        title: String,
        font: Font = .caption.weight(.semibold),
        actionSystemImage: String? = nil,
        actionAccessibilityLabel: String? = nil,
        trailingAlignmentWidth: CGFloat? = nil,
        trailingPadding: CGFloat = 0,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.font = font
        self.actionSystemImage = actionSystemImage
        self.actionAccessibilityLabel = actionAccessibilityLabel
        self.trailingAlignmentWidth = trailingAlignmentWidth
        self.trailingPadding = trailingPadding
        self.action = action
    }

    private var actionIconColor: Color {
        if colorScheme == .dark {
            return Color.primary.opacity(0.85)
        }
        return Color.primary.opacity(0.68)
    }

    private var actionBackgroundColor: Color {
        Color.primary.opacity(isActionHovered ? tokens.surfaces.raisedOpacity * 1.25 : 0)
    }

    private var actionBorderColor: Color {
        Color.primary.opacity(isActionHovered ? tokens.surfaces.hairlineOpacity * 1.3 : 0)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(font)
                .foregroundStyle(Color.primary.opacity(0.44))

            Spacer(minLength: 6)

            if let action, let actionSystemImage {
                Button(action: action) {
                    Image(systemName: actionSystemImage)
                        .font(.system(size: 13.5, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(actionIconColor)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(actionBackgroundColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(actionBorderColor)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .animation(.easeInOut(duration: tokens.motion.hoverDuration), value: isActionHovered)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actionAccessibilityLabel ?? title)
                .onHover { hovering in
                    guard isActionHovered != hovering else { return }
                    isActionHovered = hovering
                }
                .frame(width: trailingAlignmentWidth, alignment: .trailing)
                .padding(.trailing, trailingPadding)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
