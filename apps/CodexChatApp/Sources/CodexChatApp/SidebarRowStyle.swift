import CodexChatUI
import SwiftUI

struct SidebarRowButtonStyle: ButtonStyle {
    let isActive: Bool
    let accentHex: String
    let cornerRadius: CGFloat
    let isHoveredOverride: Bool?

    init(
        isActive: Bool = false,
        accentHex: String = "#10A37F",
        cornerRadius: CGFloat = 8,
        isHovered: Bool? = nil
    ) {
        self.isActive = isActive
        self.accentHex = accentHex
        self.cornerRadius = cornerRadius
        isHoveredOverride = isHovered
    }

    @State private var isHoveredInternal = false

    func makeBody(configuration: Configuration) -> some View {
        let isHovered = isHoveredOverride ?? isHoveredInternal

        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundFill(isPressed: configuration.isPressed, isHovered: isHovered))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering in
                guard isHoveredOverride == nil else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHoveredInternal = hovering
                }
            }
    }

    @ViewBuilder
    private func backgroundFill(isPressed: Bool, isHovered: Bool) -> some View {
        if isActive {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(SkillsModsTheme.sidebarRowActive)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(hex: accentHex).opacity(0.15))
                )
        } else if isPressed {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.55))
        } else if isHovered {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.38))
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
                    .fill(Color(hex: "#18A47E"))
            )
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
    }
}

struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.primary.opacity(0.44))
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}
