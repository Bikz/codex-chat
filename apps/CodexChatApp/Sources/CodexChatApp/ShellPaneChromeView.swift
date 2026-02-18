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
            HStack(spacing: 8) {
                Circle()
                    .fill(pane.processStatus == .running ? Color(hex: tokens.palette.accentHex) : Color.orange)
                    .frame(width: 8, height: 8)

                Text(pane.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(pane.cwd)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if pane.processStatus == .exited {
                    Button {
                        onRestart()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help("Restart shell")
                }

                Button {
                    onSplitHorizontal()
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Split horizontally")

                Button {
                    onSplitVertical()
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Split vertically")

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Close pane")
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.primary.opacity(isActive ? tokens.surfaces.activeOpacity : tokens.surfaces.baseOpacity))

            Divider()
                .opacity(tokens.surfaces.hairlineOpacity)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(tokens.materials.panelMaterial.material)
        .overlay(
            RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous)
                .strokeBorder(
                    isActive ? Color(hex: tokens.palette.accentHex).opacity(0.65) : Color.primary.opacity(0.12),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
    }
}
