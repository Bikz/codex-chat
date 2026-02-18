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
            .overlay(alignment: .leading) {
                if isActive {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color(hex: tokens.palette.accentHex).opacity(0.85))
                        .frame(width: 2)
                        .padding(.vertical, 5)
                        .padding(.leading, 2)
                }
            }
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
    let action: (() -> Void)?

    init(
        title: String,
        font: Font = .caption.weight(.semibold),
        actionSystemImage: String? = nil,
        actionAccessibilityLabel: String? = nil,
        trailingAlignmentWidth: CGFloat? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.font = font
        self.actionSystemImage = actionSystemImage
        self.actionAccessibilityLabel = actionAccessibilityLabel
        self.trailingAlignmentWidth = trailingAlignmentWidth
        self.action = action
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actionAccessibilityLabel ?? title)
                .frame(width: trailingAlignmentWidth, alignment: .trailing)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
