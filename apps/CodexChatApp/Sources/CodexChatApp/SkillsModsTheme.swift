import CodexChatUI
import SwiftUI

enum SkillsModsTheme {
    static let canvasBackground = Color(hex: "#F4F7F6")
    static let sidebarBackground = Color(hex: "#DCE9E7")
    static let sidebarRowActive = Color(hex: "#C8DED9")

    static let headerBackground = Color.white.opacity(0.68)
    static let cardBackground = Color.white.opacity(0.72)

    static let border = Color.primary.opacity(0.08)
    static let subtleBorder = Color.primary.opacity(0.05)
    static let mutedText = Color.primary.opacity(0.55)

    static let pageHorizontalInset: CGFloat = 24
    static let pageVerticalInset: CGFloat = 18
    static let cardRadius: CGFloat = 16
}

struct SkillsModsSearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(SkillsModsTheme.mutedText)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(SkillsModsTheme.subtleBorder)
        )
        .frame(minWidth: 220, maxWidth: 280)
    }
}

struct SkillsModsCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    @State private var isHovered = false

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: SkillsModsTheme.cardRadius, style: .continuous)
                    .fill(SkillsModsTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SkillsModsTheme.cardRadius, style: .continuous)
                    .strokeBorder(SkillsModsTheme.border)
            )
            .shadow(color: .black.opacity(isHovered ? 0.10 : 0.04), radius: isHovered ? 14 : 8, y: isHovered ? 4 : 2)
            .scaleEffect(isHovered ? 1.006 : 1)
            .animation(.easeOut(duration: 0.18), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
