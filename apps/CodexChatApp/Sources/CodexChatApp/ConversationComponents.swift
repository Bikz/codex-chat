import CodexChatCore
import CodexChatUI
import CodexKit
import Foundation
import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let tokens: DesignTokens
    let allowsExternalMarkdownContent: Bool

    var body: some View {
        let isUser = message.role == .user
        let bubbleHex = isUser ? tokens.bubbles.userBackgroundHex : tokens.bubbles.assistantBackgroundHex
        let style = tokens.bubbles.style
        let foreground = bubbleForeground(isUser: isUser, style: style)

        HStack(alignment: .top, spacing: 0) {
            if isUser {
                Spacer(minLength: 44)
            }

            messageText(message: message)
                .font(.system(size: tokens.typography.bodySize))
                .foregroundStyle(foreground)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: 560, alignment: .leading)
                .background(bubbleBackground(style: style, colorHex: bubbleHex, isUser: isUser))

            if !isUser {
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func messageText(message: ChatMessage) -> some View {
        if message.role == .assistant {
            MarkdownMessageView(
                text: message.text,
                allowsExternalContent: allowsExternalMarkdownContent
            )
        } else {
            Text(message.text)
        }
    }

    private func bubbleForeground(isUser: Bool, style: DesignTokens.BubbleStyle) -> Color {
        if isUser, style == .solid {
            return .white
        }
        return .primary
    }

    @ViewBuilder
    private func bubbleBackground(style: DesignTokens.BubbleStyle, colorHex: String, isUser: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous)

        switch style {
        case .plain:
            shape.fill(Color.clear)
        case .glass:
            shape
                .fill(tokens.materials.cardMaterial.material)
                .overlay(shape.fill(Color(hex: colorHex).opacity(isUser ? 0.14 : 0.08)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.06)))
        case .solid:
            shape
                .fill(Color(hex: colorHex))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.06)))
        }
    }
}

struct ActionCardRow: View {
    let card: ActionCard
    @State private var isExpanded = false
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous)

        DisclosureGroup(isExpanded: $isExpanded) {
            Text(card.detail)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(methodColor(card.method))
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Action: \(card.method)")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(card.title)
                            .font(.callout.weight(.semibold))
                        Text(methodCategory(card.method))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(methodColor(card.method).opacity(0.12), in: Capsule())
                            .foregroundStyle(methodColor(card.method))
                    }
                    Text(card.method)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("\(card.title) — \(card.method)")
        }
        .padding(10)
        .background(Color.primary.opacity(tokens.surfaces.baseOpacity), in: shape)
        .overlay(shape.strokeBorder(methodColor(card.method).opacity(0.32)))
    }

    private func methodColor(_ method: String) -> Color {
        let lower = method.lowercased()
        if lower.contains("write") || lower.contains("delete") || lower.contains("remove") {
            return .orange
        } else if lower.contains("exec") || lower.contains("run") || lower.contains("shell") {
            return .red
        } else if lower.contains("read") || lower.contains("search") || lower.contains("list") {
            return Color(hex: tokens.palette.accentHex)
        } else {
            return .secondary
        }
    }

    private func methodCategory(_ method: String) -> String {
        let lower = method.lowercased()
        if lower.contains("approval") {
            return "approval"
        }
        if lower.contains("write") || lower.contains("delete") || lower.contains("remove") {
            return "write"
        }
        if lower.contains("exec") || lower.contains("run") || lower.contains("shell") {
            return "exec"
        }
        if lower.contains("read") || lower.contains("search") || lower.contains("list") {
            return "read"
        }
        return "event"
    }
}

struct InstallCodexGuidanceView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            Text("Install Codex CLI")
                .font(.headline)

            Text("CodexChat needs the local `codex` binary to run app-server turns.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link("Open Codex install docs", destination: URL(string: "https://developers.openai.com/codex/cli")!)
                .buttonStyle(.borderedProminent)

            Text("After installation, use Developer → Toggle Diagnostics and press Restart Runtime.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ProjectTrustBanner: View {
    let onTrust: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)

            Text("Project is untrusted. Read-only behavior is recommended until you trust this folder.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Trust") {
                onTrust()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Trust project")
            .accessibilityHint("Marks this project folder as trusted, enabling full agent capabilities")

            Button("Settings") {
                onSettings()
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Project settings")
            .accessibilityHint("Opens safety and permission settings for this project")
        }
        .padding(10)
        .tokenCard(style: .panel)
    }
}

struct ThreadLogsDrawer: View {
    let entries: [ThreadLogEntry]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terminal / Logs")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if entries.isEmpty {
                EmptyStateView(
                    title: "No command output yet",
                    message: "Runtime command output for this thread will appear here.",
                    systemImage: "terminal"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(levelColor(entry.level))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 4)
                                    .accessibilityLabel(entry.level.rawValue)
                                Text(Self.dateFormatter.string(from: entry.timestamp))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(entry.text)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug:
            .secondary
        case .info:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}
