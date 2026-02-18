import CodexChatCore
import CodexChatUI
import SwiftUI

struct FollowUpQueueView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    @State private var editingItemID: UUID?
    @State private var editingText = ""

    var body: some View {
        let items = model.selectedFollowUpQueueItems

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: tokens.spacing.xSmall) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item: item, index: index, count: items.count)
                }
            }
            .padding(10)
            .tokenCard(style: .panel, radius: tokens.radius.large, strokeOpacity: 0.06)
            .padding(.horizontal, tokens.spacing.medium)
            .padding(.top, tokens.spacing.small)
            .accessibilityLabel("Queued follow-ups")
        }
    }

    @ViewBuilder
    private func row(item: FollowUpQueueItemRecord, index: Int, count: Int) -> some View {
        let isEditing = editingItemID == item.id

        if isEditing {
            HStack(spacing: 8) {
                TextField("Edit follow-up", text: $editingText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Edit follow-up text")

                Button("Save") {
                    saveEditing(itemID: item.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Save follow-up changes")

                Button("Cancel") {
                    cancelEditing()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Cancel follow-up edit")
            }
            .padding(8)
            .tokenCard(style: .card, strokeOpacity: 0.06)
        } else {
            HStack(spacing: 8) {
                Image(systemName: item.source == .assistantSuggestion ? "lightbulb" : "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .lineLimit(2)
                        .font(.callout)

                    HStack(spacing: 6) {
                        Text(item.dispatchMode == .auto ? "Auto" : "Manual")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if item.state == .failed {
                            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Spacer(minLength: 8)

                Button("Steer") {
                    model.steerFollowUp(item.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Steer follow-up")
                .accessibilityHint("Sends this follow-up immediately, or queues it next if steer is unavailable")

                Button {
                    model.deleteFollowUp(item.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete follow-up")
                .accessibilityLabel("Delete follow-up")

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
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("More follow-up actions")
            }
            .padding(8)
            .tokenCard(
                style: .card,
                strokeOpacity: item.state == .failed ? 0.25 : 0.06
            )
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
