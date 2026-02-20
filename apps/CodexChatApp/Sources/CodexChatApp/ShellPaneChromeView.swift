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

            controlsOverlay
                .padding(6)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
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
                .frame(width: 15, height: 15)
                .foregroundStyle(controlIconColor)
        }
        .accessibilityLabel(label)
        .accessibilityHint(ShellPathPresentation.compactPath(pane.cwd))
        .help("\(label) (\(ShellPathPresentation.compactPath(pane.cwd)))")
        .buttonStyle(.borderless)
    }

    private var shellSurfaceColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var controlGroupBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)
    }

    private var controlIconColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var activeBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.18)
    }

    private var inactiveBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
}
