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
            .background(
                backgroundFill(isPressed: configuration.isPressed, isHovered: isHovered)
                    .padding(.vertical, -(SidebarLayoutSpec.listRowSpacing / 2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        borderColor(isPressed: configuration.isPressed, isHovered: isHovered),
                        lineWidth: borderWidth(isPressed: configuration.isPressed, isHovered: isHovered)
                    )
            )
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

    private func borderColor(isPressed: Bool, isHovered: Bool) -> Color {
        if isActive {
            return Color.primary.opacity(tokens.surfaces.hairlineOpacity * 1.35)
        }
        if isPressed {
            return Color.primary.opacity(tokens.surfaces.hairlineOpacity * 1.65)
        }
        if isHovered {
            return Color.primary.opacity(tokens.surfaces.hairlineOpacity * 1.35)
        }
        return .clear
    }

    private func borderWidth(isPressed: Bool, isHovered: Bool) -> CGFloat {
        if isActive {
            return 1
        }
        if isPressed || isHovered {
            return 1
        }
        return 0
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
    let horizontalPadding: CGFloat
    let trailingPadding: CGFloat
    let leadingInset: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let actionSlotSize: CGFloat
    let actionSymbolSize: CGFloat
    let titleTracking: CGFloat
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
        horizontalPadding: CGFloat = 0,
        trailingPadding: CGFloat = 0,
        leadingInset: CGFloat = 0,
        topPadding: CGFloat = 8,
        bottomPadding: CGFloat = 4,
        actionSlotSize: CGFloat = 24,
        actionSymbolSize: CGFloat = 13.5,
        titleTracking: CGFloat = 0,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.font = font
        self.actionSystemImage = actionSystemImage
        self.actionAccessibilityLabel = actionAccessibilityLabel
        self.trailingAlignmentWidth = trailingAlignmentWidth
        self.horizontalPadding = horizontalPadding
        self.trailingPadding = trailingPadding
        self.leadingInset = leadingInset
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.actionSlotSize = actionSlotSize
        self.actionSymbolSize = actionSymbolSize
        self.titleTracking = titleTracking
        self.action = action
    }

    private var actionIconColor: Color {
        if colorScheme == .dark {
            return Color.primary.opacity(0.90)
        }
        return Color.primary.opacity(0.76)
    }

    private var actionBackgroundColor: Color {
        Color.primary.opacity(isActionHovered ? tokens.surfaces.raisedOpacity * 1.25 : 0)
    }

    private var actionBorderColor: Color {
        Color.primary.opacity(isActionHovered ? tokens.surfaces.hairlineOpacity * 1.3 : 0)
    }

    var body: some View {
        HStack(spacing: SidebarLayoutSpec.iconTextGap) {
            Text(title.uppercased())
                .font(font)
                .kerning(titleTracking)
                .foregroundStyle(Color.primary.opacity(0.44))
                .padding(.leading, leadingInset)

            Spacer(minLength: SidebarLayoutSpec.controlSlotSpacing)

            if let action, let actionSystemImage {
                Button(action: action) {
                    Image(systemName: actionSystemImage)
                        .font(.system(size: actionSymbolSize, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(actionIconColor)
                        .frame(width: actionSlotSize, height: actionSlotSize)
                        .background(
                            RoundedRectangle(cornerRadius: actionSlotSize * 0.25, style: .continuous)
                                .fill(actionBackgroundColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: actionSlotSize * 0.25, style: .continuous)
                                .strokeBorder(actionBorderColor)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: actionSlotSize * 0.25, style: .continuous))
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
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .padding(.horizontal, horizontalPadding)
    }
}
