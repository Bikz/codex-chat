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
    @Environment(\.colorScheme) private var colorScheme

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
        ZStack(alignment: .topTrailing) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onFocus)

            controlsOverlay
                .padding(6)
        }
        .background(shellSurfaceColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isActive ? activeBorderColor : inactiveBorderColor,
                    lineWidth: isActive ? 1 : 0.7
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var controlsOverlay: some View {
        HStack(spacing: 3) {
            if pane.processStatus == .exited {
                controlButton(symbol: "arrow.clockwise", label: "Restart shell", action: onRestart)
            }
            controlButton(symbol: "rectangle.split.2x1", label: "Split horizontally", action: onSplitHorizontal)
            controlButton(symbol: "rectangle.split.1x2", label: "Split vertically", action: onSplitVertical)
            controlButton(symbol: "xmark", label: "Close pane", action: onClose)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(controlGroupBackgroundColor, in: Capsule(style: .continuous))
    }

    private func controlButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(controlIconColor)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityHint(ShellPathPresentation.compactPath(pane.cwd))
        .help("\(label) (\(ShellPathPresentation.compactPath(pane.cwd)))")
        .buttonStyle(.borderless)
    }

    private var shellSurfaceColor: Color {
        Color(hex: tokens.palette.panelHex)
    }

    private var controlGroupBackgroundColor: Color {
        Color.primary.opacity(tokens.surfaces.raisedOpacity * (colorScheme == .dark ? 1.4 : 1.2))
    }

    private var controlIconColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.9 : 0.8)
    }

    private var activeBorderColor: Color {
        Color.primary.opacity(max(tokens.surfaces.activeOpacity, 0.14))
    }

    private var inactiveBorderColor: Color {
        Color.primary.opacity(max(tokens.surfaces.hairlineOpacity, 0.08))
    }
}
