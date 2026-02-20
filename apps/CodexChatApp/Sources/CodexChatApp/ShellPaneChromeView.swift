import CodexChatUI
import SwiftUI

struct ShellPaneChromeView<Content: View>: View {
    let pane: ShellPaneState
    let isActive: Bool
    let onFocus: () -> Void
    let onSplitHorizontal: () -> Void
    let onSplitVertical: () -> Void
    let onRestart: () -> Void
    let onClose: () -> Void
    private let content: () -> Content

    @Environment(\.designTokens) private var tokens

    init(
        pane: ShellPaneState,
        isActive: Bool,
        onFocus: @escaping () -> Void,
        onSplitHorizontal: @escaping () -> Void,
        onSplitVertical: @escaping () -> Void,
        onRestart: @escaping () -> Void,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.pane = pane
        self.isActive = isActive
        self.onFocus = onFocus
        self.onSplitHorizontal = onSplitHorizontal
        self.onSplitVertical = onSplitVertical
        self.onRestart = onRestart
        self.onClose = onClose
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            chromeHeader

            Divider()
                .opacity(tokens.surfaces.hairlineOpacity)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(tokens.materials.panelMaterial.material)
        .overlay(
            RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous)
                .strokeBorder(
                    isActive ? Color(hex: tokens.palette.accentHex).opacity(0.6) : Color.primary.opacity(0.08),
                    lineWidth: isActive ? 1 : 0.8
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous))
    }

    private var chromeHeader: some View {
        HStack(spacing: 6) {
            Button(action: onFocus) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(pane.processStatus == .running ? Color(hex: tokens.palette.accentHex) : Color.orange)
                        .frame(width: 6, height: 6)

                    Text(pane.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)

                    Text(ShellPathPresentation.leafName(for: pane.cwd))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(ShellPathPresentation.compactPath(pane.cwd))
            .accessibilityLabel("Focus shell pane \(pane.title)")
            .accessibilityHint("Sets this pane as active")

            if pane.processStatus == .exited {
                headerButton(symbol: "arrow.clockwise", label: "Restart shell", action: onRestart)
            }

            headerButton(symbol: "rectangle.split.2x1", label: "Split horizontally", action: onSplitHorizontal)
            headerButton(symbol: "rectangle.split.1x2", label: "Split vertically", action: onSplitVertical)
            headerButton(symbol: "xmark", label: "Close pane", action: onClose)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color.primary.opacity(isActive ? tokens.surfaces.activeOpacity * 0.8 : tokens.surfaces.baseOpacity * 0.7))
    }

    private func headerButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 17, height: 17)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .help(label)
    }
}
