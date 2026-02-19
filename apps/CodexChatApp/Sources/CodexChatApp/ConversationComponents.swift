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
    var onShowWorkerTrace: (() -> Void)?
    @State private var isExpanded = false
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous)

        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.detail)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                if let onShowWorkerTrace {
                    Button("Worker Trace") {
                        onShowWorkerTrace()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
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

struct InlineActionNoticeRow: View {
    let model: AppModel
    let card: ActionCard
    var onShowWorkerTrace: (() -> Void)?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            InlineActionDetailsList(
                actions: [card],
                model: model,
                onShowWorkerTrace: onShowWorkerTrace
            )
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(methodTint(card.method))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                Text(card.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)
                Text(isExpanded ? "Hide" : "Show")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(card.title). \(isExpanded ? "Hide details" : "Show details").")
    }

    private func methodTint(_ method: String) -> Color {
        let lower = method.lowercased()
        if lower.contains("error")
            || lower.contains("failed")
            || lower.contains("stderr")
            || lower.contains("terminated")
        {
            return .red
        }
        if lower.contains("approval") {
            return .orange
        }
        return .secondary.opacity(0.85)
    }
}

private struct TranscriptMilestoneChips: View {
    let counts: TranscriptMilestoneCounts

    var body: some View {
        HStack(spacing: 6) {
            if counts.reasoning > 0 {
                chip(title: "Reasoning", value: counts.reasoning, tint: .secondary)
            }
            if counts.commandExecution > 0 {
                chip(title: "Commands", value: counts.commandExecution, tint: .blue)
            }
            if counts.warnings > 0 {
                chip(title: "Warnings", value: counts.warnings, tint: .orange)
            }
            if counts.errors > 0 {
                chip(title: "Errors", value: counts.errors, tint: .red)
            }
        }
    }

    private func chip(title: String, value: Int, tint: Color) -> some View {
        Text("\(title) \(value)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct LiveTurnActivityRow: View {
    let activity: LiveTurnActivityPresentation
    let detailLevel: TranscriptDetailLevel
    let model: AppModel

    @State private var isExpanded = false
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Live activity")
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                Text(activity.latestActionTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if detailLevel == .balanced, activity.milestoneCounts.hasAny {
                TranscriptMilestoneChips(counts: activity.milestoneCounts)
            }

            if !activity.assistantPreview.isEmpty {
                Text(activity.assistantPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            } else if !activity.userPreview.isEmpty {
                Text(activity.userPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !activity.actions.isEmpty {
                DisclosureGroup(isExpanded: $isExpanded) {
                    InlineActionDetailsList(actions: activity.actions, model: model)
                } label: {
                    Text(isExpanded ? "Hide details" : "Show details")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(tokens.surfaces.baseOpacity), in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity)))
    }
}

struct TurnSummaryRow: View {
    let summary: TurnSummaryPresentation
    let detailLevel: TranscriptDetailLevel
    let model: AppModel

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(summary.isFailure ? .red : .secondary.opacity(0.8))
                    .frame(width: 6, height: 6)

                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Button(isExpanded ? "Hide" : "Show") {
                    isExpanded.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            if isExpanded {
                InlineActionDetailsList(actions: summary.actions, model: model)
            }
        }
    }

    private var summaryLine: String {
        var segments: [String] = []

        if summary.actionCount == 1 {
            segments.append("1 action")
        } else {
            segments.append("\(summary.actionCount) actions")
        }

        if summary.hiddenActionCount > 0 {
            segments.append("\(summary.hiddenActionCount) compacted")
        }

        if detailLevel == .balanced {
            if summary.milestoneCounts.reasoning > 0 {
                segments.append("\(summary.milestoneCounts.reasoning) reasoning")
            }
            if summary.milestoneCounts.commandExecution > 0 {
                segments.append("\(summary.milestoneCounts.commandExecution) commands")
            }
            if summary.milestoneCounts.warnings > 0 {
                segments.append("\(summary.milestoneCounts.warnings) warnings")
            }
            if summary.milestoneCounts.errors > 0 {
                segments.append("\(summary.milestoneCounts.errors) errors")
            }
        }

        return segments.joined(separator: " • ")
    }
}

private struct InlineActionDetailsList: View {
    let actions: [ActionCard]
    let model: AppModel
    var onShowWorkerTrace: (() -> Void)?

    @Environment(\.designTokens) private var tokens
    @State private var selectedWorkerTrace: AppModel.WorkerTraceEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.small) {
            ForEach(actions) { action in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(action.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        if let onShowWorkerTrace {
                            Button("Worker Trace") {
                                onShowWorkerTrace()
                            }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        } else if model.workerTraceEntry(for: action) != nil {
                            Button("Worker Trace") {
                                selectedWorkerTrace = model.workerTraceEntry(for: action)
                            }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                    }

                    Text(action.method)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)

                    Text(compactDetail(action.detail))
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 4)
            }
        }
        .padding(.top, 4)
        .sheet(item: $selectedWorkerTrace) { entry in
            WorkerTraceDetailsSheet(model: model, entry: entry)
        }
    }

    private func compactDetail(_ value: String) -> String {
        let flattened = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if flattened.count <= 220 {
            return flattened
        }
        return String(flattened.prefix(220)) + "…"
    }
}

struct WorkerTraceDetailsSheet: View {
    @ObservedObject var model: AppModel
    let entry: AppModel.WorkerTraceEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.designTokens) private var tokens

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(entry.title)
                            .font(.callout.weight(.semibold))
                        Spacer(minLength: 8)
                        Text(entry.method)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    if let turnID = entry.turnID {
                        Text("Turn ID: \(turnID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    MarkdownMessageView(
                        text: model.workerTraceMarkdown(for: entry),
                        allowsExternalContent: false
                    )
                    .font(.system(size: tokens.typography.bodySize))
                    .textSelection(.enabled)
                }
                .padding(tokens.spacing.medium)
            }
            .navigationTitle("Worker Trace")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
