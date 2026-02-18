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

struct SettingsScaffold<Sidebar: View, Content: View>: View {
    let title: String
    let subtitle: String
    let sidebarWidth: CGFloat
    let sidebar: () -> Sidebar
    let content: () -> Content

    @Environment(\.designTokens) private var tokens

    init(
        title: String,
        subtitle: String,
        sidebarWidth: CGFloat = 230,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.sidebarWidth = sidebarWidth
        self.sidebar = sidebar
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.medium) {
            VStack(alignment: .leading, spacing: tokens.spacing.xSmall) {
                Text(title)
                    .font(.title)
                    .fontWeight(.semibold)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: tokens.spacing.medium) {
                VStack(alignment: .leading, spacing: tokens.spacing.xSmall) {
                    sidebar()
                }
                .padding(tokens.spacing.small)
                .frame(width: sidebarWidth, alignment: .topLeading)
                .settingsFlatSurface(fillColor: Color(hex: tokens.palette.sidebarHex), borderColor: Color.primary.opacity(0.08))

                VStack(alignment: .leading, spacing: tokens.spacing.small) {
                    content()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(tokens.spacing.small)
                .settingsFlatSurface(fillColor: Color(hex: tokens.palette.panelHex), borderColor: Color.primary.opacity(0.08))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(tokens.spacing.large)
        .background(Color(hex: tokens.palette.backgroundHex))
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
            .foregroundStyle(isSelected ? Color(hex: tokens.palette.accentHex) : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous)
                    .fill(isSelected ? Color(hex: tokens.palette.accentHex).opacity(0.10) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous)
                    .strokeBorder(isSelected ? Color(hex: tokens.palette.accentHex).opacity(0.30) : .clear)
            )
        }
        .buttonStyle(.plain)
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

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(tokens.spacing.medium)
        .settingsFlatSurface(fillColor: backgroundFill, borderColor: Color.primary.opacity(0.08))
    }

    private var backgroundFill: Color {
        let panel = Color(hex: tokens.palette.panelHex)
        return switch emphasis {
        case .primary:
            panel
        case .secondary:
            panel.opacity(0.82)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(textColor)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor)
            )
    }

    private var textColor: Color {
        switch tone {
        case .neutral:
            .primary
        case .accent:
            Color(hex: tokens.palette.accentHex)
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral:
            Color.primary.opacity(0.08)
        case .accent:
            Color(hex: tokens.palette.accentHex).opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .neutral:
            Color.primary.opacity(0.12)
        case .accent:
            Color(hex: tokens.palette.accentHex).opacity(0.26)
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

private struct SettingsFlatSurface: ViewModifier {
    let fillColor: Color
    let borderColor: Color
    @Environment(\.designTokens) private var tokens

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }
}

private extension View {
    func settingsFlatSurface(fillColor: Color, borderColor: Color) -> some View {
        modifier(SettingsFlatSurface(fillColor: fillColor, borderColor: borderColor))
    }
}
