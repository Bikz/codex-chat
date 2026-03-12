import CodexChatCore
import CodexChatUI
import SwiftUI

struct FollowUpQueueView: View {
    struct PlanSummary: Equatable {
        let title: String
        let subtitle: String
        let visibleTasks: [TaskSummary]
        let hasOverflowTasks: Bool
        let status: PlanRunStatus
    }

    struct TaskSummary: Equatable, Identifiable {
        let id: String
        let title: String
        let status: PlanTaskRunStatus
    }

    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @Environment(\.colorScheme) private var colorScheme

    @State private var editingItemID: UUID?
    @State private var editingText = ""

    var body: some View {
        let items = model.selectedFollowUpQueueItems
        let planSummary = Self.planSummary(
            activePlanRun: model.activePlanRun,
            taskStates: model.planRunnerTaskStates,
            selectedThreadID: model.selectedThreadID
        )

        if !items.isEmpty || planSummary != nil {
            VStack(alignment: .leading, spacing: tokens.spacing.small) {
                if let planSummary {
                    planHeader(summary: planSummary)
                }

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item: item, index: index, count: items.count)
                }
            }
            .padding(.horizontal, tokens.spacing.medium)
            .padding(.top, tokens.spacing.small)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Queued follow-ups")
        }
    }

    static func compactTitle(for item: FollowUpQueueItemRecord) -> String {
        switch item.source {
        case .userQueued:
            return "Continue"
        case .assistantSuggestion:
            let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Continue" : trimmed
        }
    }

    static func shouldShowVerboseText(for item: FollowUpQueueItemRecord) -> Bool {
        item.source == .assistantSuggestion || item.state == .failed
    }

    static func planSummary(
        activePlanRun: PlanRunRecord?,
        taskStates: [PlanRunTaskRecord],
        selectedThreadID: UUID?
    ) -> PlanSummary? {
        guard let activePlanRun,
              let selectedThreadID,
              activePlanRun.threadID == selectedThreadID,
              activePlanRun.status == .pending || activePlanRun.status == .running
        else {
            return nil
        }

        let totalTasks = max(activePlanRun.totalTasks, taskStates.count)
        let completedTasks = max(
            activePlanRun.completedTasks,
            taskStates.count(where: { $0.status == .completed })
        )
        let subtitle = "\(completedTasks) of \(max(totalTasks, 1)) tasks completed"
        let visibleTasks = taskStates
            .prefix(3)
            .map { TaskSummary(id: $0.taskID, title: $0.title, status: $0.status) }

        return PlanSummary(
            title: activePlanRun.title,
            subtitle: subtitle,
            visibleTasks: visibleTasks,
            hasOverflowTasks: taskStates.count > visibleTasks.count,
            status: activePlanRun.status
        )
    }

    private func planHeader(summary: PlanSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: planStatusSymbol(summary.status))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(planStatusColor(summary.status))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.subtitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(summary.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Button {
                    model.isPlanRunnerSheetVisible = true
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open plan details")
            }

            if !summary.visibleTasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.visibleTasks) { task in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: planTaskSymbol(task.status))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(planTaskColor(task.status))
                                .padding(.top, 4)
                                .accessibilityHidden(true)

                            Text(task.title)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }

                    if summary.hasOverflowTasks {
                        Text("More tasks in plan")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(planHeaderBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func row(item: FollowUpQueueItemRecord, index: Int, count: Int) -> some View {
        let isEditing = editingItemID == item.id

        if isEditing {
            editingRow(itemID: item.id)
        } else {
            compactRow(item: item, index: index, count: count)
        }
    }

    private func editingRow(itemID: UUID) -> some View {
        HStack(spacing: 8) {
            TextField("Edit follow-up", text: $editingText)
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
                )
                .accessibilityLabel("Edit follow-up text")

            Button("Save") {
                saveEditing(itemID: itemID)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("Cancel") {
                cancelEditing()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
        )
    }

    private func compactRow(item: FollowUpQueueItemRecord, index: Int, count: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: itemIcon(item))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(item.state == .failed ? .red : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.compactTitle(for: item))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if Self.shouldShowVerboseText(for: item) {
                    let detail = item.state == .failed ? (item.lastError ?? item.text) : item.text
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(item.state == .failed ? .red.opacity(0.9) : .secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: 6) {
                Button("Steer") {
                    model.steerFollowUp(item.id)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.82))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.055))
                )
                .accessibilityHint("Send this follow-up now if available")

                Menu {
                    Button {
                        beginEditing(item)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button {
                        model.moveFollowUpUp(item.id)
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    .disabled(index == 0)

                    Button {
                        model.moveFollowUpDown(item.id)
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                    .disabled(index == count - 1)

                    Divider()

                    Button {
                        model.setFollowUpDispatchMode(.auto, for: item.id)
                    } label: {
                        Label("Set Auto", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }

                    Button {
                        model.setFollowUpDispatchMode(.manual, for: item.id)
                    } label: {
                        Label("Set Manual", systemImage: "hand.raised")
                    }

                    if item.state == .failed {
                        Divider()
                        Button {
                            model.retryFailedFollowUp(item.id)
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        model.deleteFollowUp(item.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.04))
                        )
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("More follow-up actions")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(cardBackground(item))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(cardStrokeColor(item))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var planHeaderBackground: some View {
        LinearGradient(
            colors: [
                Color.primary.opacity(colorScheme == .dark ? 0.065 : 0.04),
                Color(hex: tokens.palette.panelHex).opacity(0.92),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(hex: tokens.palette.panelHex).opacity(colorScheme == .dark ? 0.9 : 0.96))
    }

    private func cardBackground(_ item: FollowUpQueueItemRecord) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                item.state == .failed
                    ? Color.red.opacity(colorScheme == .dark ? 0.12 : 0.08)
                    : Color(hex: tokens.palette.panelHex).opacity(colorScheme == .dark ? 0.9 : 0.96)
            )
    }

    private func cardStrokeColor(_ item: FollowUpQueueItemRecord) -> Color {
        if item.state == .failed {
            return Color.red.opacity(colorScheme == .dark ? 0.28 : 0.22)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)
    }

    private func itemIcon(_ item: FollowUpQueueItemRecord) -> String {
        if item.state == .failed {
            return "exclamationmark.circle"
        }
        return switch item.source {
        case .userQueued:
            "arrow.turn.down.right"
        case .assistantSuggestion:
            "sparkles"
        }
    }

    private func planStatusSymbol(_ status: PlanRunStatus) -> String {
        switch status {
        case .pending, .running:
            "checklist"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .cancelled:
            "xmark.circle.fill"
        }
    }

    private func planStatusColor(_ status: PlanRunStatus) -> Color {
        switch status {
        case .pending, .running:
            .secondary
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .orange
        }
    }

    private func planTaskSymbol(_ status: PlanTaskRunStatus) -> String {
        switch status {
        case .pending:
            "circle"
        case .running:
            "arrow.triangle.2.circlepath"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "xmark.circle.fill"
        case .skipped:
            "minus.circle"
        }
    }

    private func planTaskColor(_ status: PlanTaskRunStatus) -> Color {
        switch status {
        case .pending:
            .secondary
        case .running:
            .secondary
        case .completed:
            .green
        case .failed:
            .red
        case .skipped:
            .orange
        }
    }

    private func beginEditing(_ item: FollowUpQueueItemRecord) {
        editingItemID = item.id
        editingText = item.text
    }

    private func saveEditing(itemID: UUID) {
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        model.updateFollowUpText(trimmed, id: itemID)
        cancelEditing()
    }

    private func cancelEditing() {
        editingItemID = nil
        editingText = ""
    }
}
