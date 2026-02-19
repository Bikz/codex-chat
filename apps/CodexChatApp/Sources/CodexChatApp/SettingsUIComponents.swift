import CodexChatUI
import SwiftUI

enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case account
    case runtime
    case generalProject
    case safetyDefaults
    case experimental
    case diagnostics
    case storage

    static let defaultSelection: SettingsSection = .account

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .account:
            "Account"
        case .runtime:
            "Runtime"
        case .generalProject:
            "General Project"
        case .safetyDefaults:
            "Safety Defaults"
        case .experimental:
            "Experimental"
        case .diagnostics:
            "Diagnostics"
        case .storage:
            "Storage"
        }
    }

    var symbolName: String {
        switch self {
        case .account:
            "person.crop.circle"
        case .runtime:
            "cpu"
        case .generalProject:
            "folder"
        case .safetyDefaults:
            "shield"
        case .experimental:
            "flask"
        case .diagnostics:
            "waveform.path.ecg"
        case .storage:
            "externaldrive"
        }
    }
}

enum SettingsSectionCardEmphasis {
    case primary
    case secondary
}

struct SettingsInlineHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String?

    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3.weight(.semibold))

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSidebarItem: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.designTokens) private var tokens

    var body: some View {
        Button(action: action) {
            HStack(spacing: tokens.spacing.small) {
                Image(systemName: symbolName)
                    .font(.subheadline)
                    .frame(width: 16)

                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 34, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.05) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary.opacity(0.10) : .clear)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color(hex: tokens.palette.accentHex))
                    .frame(width: 2, height: 16)
                    .padding(.leading, 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let emphasis: SettingsSectionCardEmphasis
    let content: Content

    @Environment(\.designTokens) private var tokens

    init(
        title: String,
        subtitle: String? = nil,
        emphasis: SettingsSectionCardEmphasis = .primary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.emphasis = emphasis
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.small) {
            Text(title)
                .font(.headline)
                .foregroundStyle(emphasis == .primary ? .primary : .secondary)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(tokens.spacing.small)
        .tokenCard(
            style: cardStyle,
            radius: tokens.radius.small,
            strokeOpacity: borderOpacity
        )
    }

    private var cardStyle: TokenCardStyle {
        switch emphasis {
        case .primary:
            .card
        case .secondary:
            .panel
        }
    }

    private var borderOpacity: Double {
        switch emphasis {
        case .primary:
            0.08
        case .secondary:
            0.06
        }
    }
}

struct SettingsStatusBadge: View {
    enum Tone {
        case neutral
        case accent
    }

    let text: String
    let tone: Tone

    @Environment(\.designTokens) private var tokens

    init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(textColor)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor)
            )
    }

    private var textColor: Color {
        switch tone {
        case .neutral:
            .secondary
        case .accent:
            .primary
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral:
            Color.clear
        case .accent:
            Color.primary.opacity(0.04)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .neutral:
            Color.primary.opacity(0.16)
        case .accent:
            Color.primary.opacity(0.22)
        }
    }
}

struct SettingsFieldRow<Content: View>: View {
    let label: String
    let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
