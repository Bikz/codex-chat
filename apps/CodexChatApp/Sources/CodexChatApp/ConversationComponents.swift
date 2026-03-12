import CodexChatCore
import CodexChatUI
import CodexKit
import Foundation
import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let tokens: DesignTokens
    let allowsExternalMarkdownContent: Bool
    let projectPath: String?

    var body: some View {
        let isUser = message.role == .user
        let isProgress = message.role == .system
        let bubbleHex = tokens.bubbles.userBackgroundHex
        let style = tokens.bubbles.style
        let foreground = bubbleForeground(isUser: isUser, style: style)

        if isUser {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 44)

                messageText(message: message)
                    .font(.system(size: tokens.typography.bodySize))
                    .foregroundStyle(foreground)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: 560, alignment: .leading)
                    .background(bubbleBackground(style: style, colorHex: bubbleHex, isUser: true))
            }
            .frame(maxWidth: .infinity)
        } else if isProgress {
            messageText(message: message)
                .font(.system(size: max(tokens.typography.bodySize - 2, 13)))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            messageText(message: message)
                .font(.system(size: tokens.typography.bodySize))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func messageText(message: ChatMessage) -> some View {
        if message.role == .assistant {
            MarkdownMessageView(
                text: message.text,
                allowsExternalContent: allowsExternalMarkdownContent,
                projectPath: projectPath
            )
        } else {
            Text(message.text)
        }
    }

    private func bubbleForeground(isUser: Bool, style: DesignTokens.BubbleStyle) -> Color {
        if isUser {
            return style == .plain ? .primary : Color.white.opacity(0.96)
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
        let state = RuntimeVisualStateClassifier.classify(card)
        let tint = toneColor(state.tone)
        let shape = RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous)

        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(RuntimeVisualStateClassifier.detailPreview(for: card, maxLength: 800))
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
                Image(systemName: state.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                    .accessibilityLabel(state.label)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(RuntimeVisualStateClassifier.conciseTitle(for: card))
                            .font(.callout.weight(.semibold))
                        Text(state.label)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tint.opacity(0.14), in: Capsule())
                            .foregroundStyle(tint)
                    }
                    Text(card.method)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("\(card.title) — \(card.method)")
        }
        .padding(10)
        .background(
            Color(hex: tokens.palette.panelHex).opacity(0.94),
            in: shape
        )
        .overlay(shape.strokeBorder(tint.opacity(0.32)))
    }

    private func toneColor(_ tone: RuntimeVisualStateTone) -> Color {
        switch tone {
        case .neutral:
            .secondary
        case .accent:
            .primary
        case .success:
            .primary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

struct InlineActionNoticeRow: View {
    let model: AppModel
    let card: ActionCard
    var onShowWorkerTrace: (() -> Void)?
    @State private var isExpanded = false

    var body: some View {
        let state = RuntimeVisualStateClassifier.classify(card)
        let tint = toneColor(state.tone)
        let backgroundTint = tint.opacity(state.tone == .error ? 0.08 : 0.05)
        let borderTint = tint.opacity(state.tone == .error ? 0.18 : 0.1)

        DisclosureGroup(isExpanded: $isExpanded) {
            InlineActionDetailsList(
                actions: [card],
                model: model,
                onShowWorkerTrace: onShowWorkerTrace
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: state.iconName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 12)
                    .accessibilityHidden(true)

                Text(state.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.1), in: Capsule())

                Text(RuntimeVisualStateClassifier.conciseTitle(for: card))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)
                Text(isExpanded ? "Hide" : "Show")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary.opacity(0.66))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderTint)
        )
        .accessibilityLabel("\(card.title). \(isExpanded ? "Hide details" : "Show details").")
    }

    private func toneColor(_ tone: RuntimeVisualStateTone) -> Color {
        switch tone {
        case .neutral:
            .secondary.opacity(0.85)
        case .accent:
            .primary.opacity(0.85)
        case .success:
            .primary.opacity(0.85)
        case .warning:
            .orange
        case .error:
            .red
        }
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
                chip(title: "Commands", value: counts.commandExecution, tint: .primary)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var compactStatusPulse = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(Color.primary.opacity(compactStatusOpacity))
                    .frame(width: 6, height: 6)
                    .scaleEffect(compactStatusScale)
                    .accessibilityHidden(true)

                Text("\(presentation.statusLabel)…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(compactStatusOpacity)

                Spacer(minLength: 8)

                if canExpandDetails {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Hide details" : "Show details")
                                .font(.caption2.weight(.medium))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.secondary.opacity(0.68))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !collapsedActivityItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(collapsedActivityItems) { item in
                        liveTimelineItem(item)
                    }
                }
            } else if let preview = livePreviewText {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            if isExpanded, activity.milestoneCounts.hasAny {
                TranscriptMilestoneChips(counts: activity.milestoneCounts)
            }

            if isExpanded {
                if let commandOutputPreview = activity.commandOutputPreview {
                    InlineTerminalPreview(preview: commandOutputPreview)
                }

                if presentation.showTraceBox {
                    liveTraceBox
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .onAppear {
            if detailLevel == .detailed {
                isExpanded = true
            }
            updateCompactStatusPulse()
        }
        .onChange(of: presentation.showTraceBox) { _, _ in
            updateCompactStatusPulse()
        }
        .onChange(of: detailLevel) { _, newValue in
            if newValue == .detailed {
                isExpanded = true
            }
        }
        .onChange(of: reduceMotion) { _, _ in
            updateCompactStatusPulse()
        }
    }

    private var presentation: LiveActivityTraceFormatter.Presentation {
        LiveActivityTraceFormatter.buildPresentation(
            actions: activity.actions,
            fallbackTitle: activity.latestActionTitle,
            detailLevel: detailLevel
        )
    }

    private var compactStatusOpacity: Double {
        guard !reduceMotion else { return 1 }
        return compactStatusPulse ? 0.72 : 1
    }

    private var compactStatusScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return compactStatusPulse ? 0.99 : 1
    }

    private var canExpandDetails: Bool {
        detailLevel == .detailed || presentation.showTraceBox || activity.commandOutputPreview != nil
    }

    private var livePreviewText: String? {
        let trimmedAssistant = activity.assistantPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAssistant.isEmpty else {
            return nil
        }
        return trimmedAssistant
    }

    private var collapsedTraceLines: [LiveActivityTraceFormatter.Line] {
        Array(presentation.lines.suffix(2))
    }

    private var collapsedActivityItems: [CollapsedActivityItem] {
        var items = latestActionItems
        if items.isEmpty {
            items = collapsedTraceLines.map {
                CollapsedActivityItem(id: $0.id, iconName: "circle.fill", text: $0.text, emphasis: .secondary)
            }
        }

        if let preview = livePreviewText, !items.contains(where: { $0.text == preview }) {
            items.append(
                CollapsedActivityItem(
                    id: UUID(),
                    iconName: "text.bubble",
                    text: preview,
                    emphasis: .secondary
                )
            )
        }

        return Array(items.prefix(3))
    }

    private var latestActionItems: [CollapsedActivityItem] {
        activity.actions
            .suffix(3)
            .map { action in
                let state = RuntimeVisualStateClassifier.classify(action)
                return CollapsedActivityItem(
                    id: action.id,
                    iconName: state.iconName,
                    text: RuntimeVisualStateClassifier.conciseTitle(for: action),
                    emphasis: emphasis(for: state.tone)
                )
            }
    }

    private func liveTimelineItem(_ item: CollapsedActivityItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.iconName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.emphasis.color.opacity(0.9))
                .frame(width: 14)
                .accessibilityHidden(true)

            Text(item.text)
                .font(.caption)
                .foregroundStyle(item.emphasis.textStyle)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func emphasis(for tone: RuntimeVisualStateTone) -> CollapsedActivityItem.Emphasis {
        switch tone {
        case .neutral:
            .secondary
        case .accent, .success:
            .primary
        case .warning:
            .warning
        case .error:
            .error
        }
    }

    private var liveTraceBox: some View {
        Group {
            if presentation.lines.isEmpty {
                Text("Waiting for trace events…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(presentation.lines) { line in
                                Text(line.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onAppear {
                        if let lastID = presentation.lines.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                    .onChange(of: presentation.lines.count) { _, _ in
                        guard let lastID = presentation.lines.last?.id else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 52, idealHeight: 86, maxHeight: 120)
    }

    private func updateCompactStatusPulse() {
        guard !reduceMotion else {
            compactStatusPulse = false
            return
        }

        compactStatusPulse = false
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            compactStatusPulse = true
        }
    }
}

private struct CollapsedActivityItem: Identifiable {
    enum Emphasis {
        case primary
        case secondary
        case warning
        case error

        var color: Color {
            switch self {
            case .primary:
                .primary
            case .secondary:
                .secondary
            case .warning:
                .orange
            case .error:
                .red
            }
        }

        var textStyle: Color {
            switch self {
            case .primary:
                .primary.opacity(0.92)
            case .secondary:
                .secondary.opacity(0.92)
            case .warning:
                .orange.opacity(0.96)
            case .error:
                .red.opacity(0.96)
            }
        }
    }

    let id: UUID
    let iconName: String
    let text: String
    let emphasis: Emphasis
}

private struct InlineTerminalPreview: View {
    let preview: CommandOutputPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("Terminal", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)
                Text("\(preview.totalLineCount) lines")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(preview.lines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(levelColor(line.level))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 5)
                                    .accessibilityHidden(true)
                                Text(line.text)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    if let lastID = preview.lines.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
                .onChange(of: preview.lines.count) { _, _ in
                    guard let lastID = preview.lines.last?.id else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .frame(minHeight: 66, idealHeight: 114, maxHeight: 180)

            if preview.isTruncated {
                Text("Showing latest output in chat.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug:
            .secondary
        case .info:
            .primary.opacity(0.82)
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

struct TurnSummaryRow: View {
    let summary: TurnSummaryPresentation
    let detailLevel: TranscriptDetailLevel
    let model: AppModel
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    dividerLine

                    HStack(spacing: 6) {
                        Text(summaryLine)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(summaryTint)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary.opacity(0.58))
                    }

                    dividerLine
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Turn activity")
            .accessibilityValue(summaryLine)
            .accessibilityHint(isExpanded ? "Collapses details" : "Expands details")

            if isExpanded {
                if let detailOverviewLine {
                    Text(detailOverviewLine)
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.88))
                }

                if summary.milestoneCounts.hasAny {
                    TranscriptMilestoneChips(counts: summary.milestoneCounts)
                }

                TurnSummaryDetailsList(actions: summary.actions, model: model)
            }
        }
    }

    private var summaryLine: String {
        let durationLabel = formatDuration(summary.duration)
        if summary.isFailure || summary.milestoneCounts.errors > 0 {
            return "Worked for \(durationLabel) • issue"
        }
        return "Worked for \(durationLabel)"
    }

    private var summaryTint: Color {
        summary.isFailure ? .red : .secondary.opacity(0.92)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private var detailOverviewLine: String? {
        var parts: [String] = []
        if let explorationSummaryLine {
            parts.append(explorationSummaryLine)
        }
        if summary.hiddenActionCount > 0, detailLevel == .balanced {
            parts.append("\(summary.hiddenActionCount) compacted")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var explorationSummaryLine: String? {
        var fileCount = 0
        var searchCount = 0

        for action in summary.actions where !isLifecycle(action) {
            let text = "\(action.title) \(action.method) \(action.detail)".lowercased()

            if text.contains("search") {
                searchCount += 1
                continue
            }

            if text.contains("read")
                || text.contains(".swift")
                || text.contains(".md")
                || text.contains(".json")
                || text.contains(".yaml")
                || text.contains(".yml")
                || text.contains(".toml")
            {
                fileCount += 1
            }
        }

        guard fileCount > 0 || searchCount > 0 else {
            return nil
        }

        var parts: [String] = []
        if fileCount > 0 {
            parts.append("\(fileCount) \(fileCount == 1 ? "file" : "files")")
        }
        if searchCount > 0 {
            parts.append("\(searchCount) \(searchCount == 1 ? "search" : "searches")")
        }
        return "Explored " + parts.joined(separator: ", ")
    }

    private func isLifecycle(_ action: ActionCard) -> Bool {
        let method = action.method.lowercased()
        return [
            "item/started",
            "item/completed",
            "turn/started",
            "turn/completed",
        ].contains(method)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        if totalSeconds < 1 {
            return "a moment"
        }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

private struct TurnSummaryDetailsList: View {
    let actions: [ActionCard]
    let model: AppModel

    @State private var selectedWorkerTrace: AppModel.WorkerTraceEntry?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(visibleActions) { action in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(tint(for: action))
                                .frame(width: 4)
                                .padding(.vertical, 2)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(primaryLine(for: action))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary.opacity(0.92))
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Text(RuntimeVisualStateClassifier.classify(action).label)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(tint(for: action))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(tint(for: action).opacity(0.11), in: Capsule())
                                }

                                let detail = RuntimeVisualStateClassifier.detailPreview(for: action, maxLength: 240)
                                if !detail.isEmpty {
                                    Text(detail)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary.opacity(0.92))
                                        .textSelection(.enabled)
                                        .lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            Spacer(minLength: 8)

                            if model.workerTraceEntry(for: action) != nil {
                                Button {
                                    selectedWorkerTrace = model.workerTraceEntry(for: action)
                                } label: {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.caption2.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary.opacity(0.78))
                                .accessibilityLabel("Open worker trace for \(primaryLine(for: action))")
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06))
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 210)
        .sheet(item: $selectedWorkerTrace) { entry in
            WorkerTraceDetailsSheet(model: model, entry: entry)
        }
    }

    private var visibleActions: [ActionCard] {
        let filtered = actions.filter { action in
            let method = action.method.lowercased()
            return ![
                "item/started",
                "item/completed",
                "turn/started",
                "turn/completed",
            ].contains(method)
        }
        return filtered.isEmpty ? actions : filtered
    }

    private func primaryLine(for action: ActionCard) -> String {
        let title = RuntimeVisualStateClassifier.conciseTitle(for: action)
        if !title.isEmpty {
            return title
        }

        let detail = compactWhitespace(action.detail)
        if !detail.isEmpty {
            return detail
        }

        return action.method
    }

    private func tint(for action: ActionCard) -> Color {
        let state = RuntimeVisualStateClassifier.classify(action)
        switch state.tone {
        case .neutral:
            return .secondary.opacity(0.9)
        case .accent:
            return .primary.opacity(0.88)
        case .success:
            return .primary.opacity(0.88)
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func compactWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
                        Text(RuntimeVisualStateClassifier.conciseTitle(for: action))
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

                    Text(RuntimeVisualStateClassifier.detailPreview(for: action))
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
