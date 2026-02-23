import CodexChatUI
import SwiftUI

enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case account
    case appearance
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
        case .appearance:
            "Appearance"
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
        case .appearance:
            "paintpalette"
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

    var subtitle: String {
        switch self {
        case .account:
            "Authentication and identity preferences."
        case .appearance:
            "Theme, gradients, and transparency controls."
        case .runtime:
            "Model defaults and runtime behavior."
        case .generalProject:
            "Baseline project trust and memory settings."
        case .safetyDefaults:
            "Default safety posture for newly created projects."
        case .experimental:
            "Advanced capabilities gated behind confirmations."
        case .diagnostics:
            "Support bundle and troubleshooting exports."
        case .storage:
            "Managed paths, migration, and repair tools."
        }
    }
}

enum SettingsSectionCardEmphasis {
    case primary
    case secondary
}

enum SettingsLiquidGlassStyle {
    struct ContainerStyle: Equatable {
        let strokeOpacity: Double
        let shadowRadius: CGFloat
    }

    struct SelectionStyle: Equatable {
        let fillOpacity: Double
        let strokeOpacity: Double
        let indicatorOpacity: Double
    }

    static let safeAreaExtensionEdges: Edge.Set = .top

    static func sidebarContainerStyle(glassEnabled: Bool) -> ContainerStyle {
        ContainerStyle(
            strokeOpacity: glassEnabled ? 0.14 : 0.08,
            shadowRadius: glassEnabled ? 0 : 6
        )
    }

    static func sectionCardStyle(
        emphasis: SettingsSectionCardEmphasis,
        glassEnabled: Bool
    ) -> ContainerStyle {
        let baseOpacity = switch emphasis {
        case .primary:
            0.10
        case .secondary:
            0.08
        }

        return ContainerStyle(
            strokeOpacity: glassEnabled ? baseOpacity + 0.05 : baseOpacity - 0.02,
            shadowRadius: glassEnabled ? 0 : 4
        )
    }

    static func sidebarSelectionStyle(
        isSelected: Bool,
        glassEnabled: Bool
    ) -> SelectionStyle {
        guard isSelected else {
            return SelectionStyle(fillOpacity: 0, strokeOpacity: 0, indicatorOpacity: 0)
        }
        return SelectionStyle(
            fillOpacity: glassEnabled ? 0.12 : 0.07,
            strokeOpacity: glassEnabled ? 0.22 : 0.10,
            indicatorOpacity: 1
        )
    }
}

struct SettingsInlineHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    let symbolName: String?

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        symbolName: String? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.12))
                    )
            }

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsHeroHeader<Accessory: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    let symbolName: String
    private let accessory: Accessory

    @Environment(\.designTokens) private var tokens
    @Environment(\.glassSurfacesEnabled) private var glassSurfacesEnabled

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        symbolName: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.accessory = accessory()
    }

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        symbolName: String
    ) where Accessory == EmptyView {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName
        ) {
            EmptyView()
        }
    }

    var body: some View {
        let style = SettingsLiquidGlassStyle.sectionCardStyle(
            emphasis: .secondary,
            glassEnabled: glassSurfacesEnabled
        )

        return HStack(alignment: .top, spacing: tokens.spacing.small) {
            SettingsInlineHeader(
                eyebrow: eyebrow,
                title: title,
                subtitle: subtitle,
                symbolName: symbolName
            )

            Spacer(minLength: 0)
            accessory
        }
        .padding(tokens.spacing.small)
        .tokenCard(
            style: .panel,
            radius: tokens.radius.medium,
            strokeOpacity: style.strokeOpacity,
            shadowRadius: style.shadowRadius
        )
    }
}

struct SettingsSidebarItem: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.designTokens) private var tokens
    @Environment(\.glassSurfacesEnabled) private var glassSurfacesEnabled

    var body: some View {
        let selectionStyle = SettingsLiquidGlassStyle.sidebarSelectionStyle(
            isSelected: isSelected,
            glassEnabled: glassSurfacesEnabled
        )

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
            .frame(minHeight: 36, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous)
                    .fill(Color.primary.opacity(selectionStyle.fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous)
                    .strokeBorder(Color.primary.opacity(selectionStyle.strokeOpacity))
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color(hex: tokens.palette.accentHex))
                    .frame(width: 2, height: 16)
                    .padding(.leading, 2)
                    .opacity(selectionStyle.indicatorOpacity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let emphasis: SettingsSectionCardEmphasis
    let content: Content

    @Environment(\.designTokens) private var tokens
    @Environment(\.glassSurfacesEnabled) private var glassSurfacesEnabled

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
        let style = SettingsLiquidGlassStyle.sectionCardStyle(
            emphasis: emphasis,
            glassEnabled: glassSurfacesEnabled
        )

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
            radius: tokens.radius.medium,
            strokeOpacity: style.strokeOpacity,
            shadowRadius: style.shadowRadius
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
