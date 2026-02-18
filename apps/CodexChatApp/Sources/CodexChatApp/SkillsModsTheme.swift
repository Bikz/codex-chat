import CodexChatUI
import SwiftUI

enum SkillsModsTheme {
    static let pageHorizontalInset: CGFloat = 24
    static let pageVerticalInset: CGFloat = 18
    static let cardRadius: CGFloat = 16

    static func canvasBackground(tokens: DesignTokens) -> Color {
        Color.primary.opacity(tokens.surfaces.baseOpacity * 0.8)
    }

    static func headerBackground(tokens: DesignTokens) -> Color {
        Color.primary.opacity(tokens.surfaces.baseOpacity)
    }

    static func cardBackground(tokens: DesignTokens) -> Color {
        Color.primary.opacity(tokens.surfaces.raisedOpacity)
    }

    static func activeBackground(tokens: DesignTokens) -> Color {
        Color.primary.opacity(tokens.surfaces.activeOpacity)
    }

    static func border(tokens: DesignTokens) -> Color {
        Color.primary.opacity(tokens.surfaces.hairlineOpacity)
    }

    static func subtleBorder(tokens: DesignTokens) -> Color {
        Color.primary.opacity(tokens.surfaces.hairlineOpacity * 0.7)
    }

    static func mutedText(tokens: DesignTokens) -> Color {
        Color.primary.opacity(tokens.surfaces.activeOpacity * 4.5)
    }
}

struct SkillsModsSearchField: View {
    @Binding var text: String
    var placeholder: String
    @Environment(\.designTokens) private var tokens

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(SkillsModsTheme.mutedText(tokens: tokens))

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
                .fill(SkillsModsTheme.cardBackground(tokens: tokens))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(SkillsModsTheme.subtleBorder(tokens: tokens))
        )
        .frame(minWidth: 220, maxWidth: 280)
    }
}

struct SkillsModsCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    @State private var isHovered = false
    @Environment(\.designTokens) private var tokens

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: SkillsModsTheme.cardRadius, style: .continuous)
                    .fill(SkillsModsTheme.cardBackground(tokens: tokens))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SkillsModsTheme.cardRadius, style: .continuous)
                    .strokeBorder(SkillsModsTheme.border(tokens: tokens))
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: SkillsModsTheme.cardRadius, style: .continuous)
                    .strokeBorder(SkillsModsTheme.activeBackground(tokens: tokens), lineWidth: 1)
                    .opacity(isHovered ? 0.55 : 0)
            }
            .animation(.easeOut(duration: tokens.motion.hoverDuration), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
