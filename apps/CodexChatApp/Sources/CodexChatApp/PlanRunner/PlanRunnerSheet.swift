import CodexChatCore
import CodexChatUI
import SwiftUI

struct PlanRunnerSheet: View {
    @ObservedObject var model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.designTokens) private var tokens

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionCard(
                        title: "Plan Source",
                        subtitle: "Load from a markdown file path or edit the plan text directly."
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("/absolute/path/to/plan.md", text: $model.planRunnerSourcePath)
                                    .textFieldStyle(.roundedBorder)

                                Button("Load") {
                                    Task {
                                        await model.hydratePlanRunnerDraftFromPathIfNeeded()
                                    }
                                }
                                .buttonStyle(.bordered)
                            }

                            TextEditor(text: $model.planRunnerDraftText)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(minHeight: 240)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.12))
                                )
                        }
                    }

                    SettingsSectionCard(
                        title: "Execution",
                        subtitle: model.isMultiAgentEnabledForPlanRunner
                            ? "Parallel batches are enabled when dependencies allow."
                            : "Multi-agent is disabled in config; execution falls back to sequential batches."
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Stepper(value: $model.planRunnerPreferredBatchSize, in: 1 ... 12) {
                                Text("Preferred batch size: \(model.planRunnerPreferredBatchSize)")
                                    .font(.callout)
                            }

                            HStack(spacing: 8) {
                                Button("Start Run") {
                                    model.startPlanRunnerExecution()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isPlanRunnerExecuting)

                                Button("Cancel") {
                                    model.cancelPlanRunnerExecution()
                                }
                                .buttonStyle(.bordered)
                                .disabled(!model.isPlanRunnerExecuting)

                                Button("Reload Latest") {
                                    Task {
                                        await model.loadLatestPlanRunForSelectedThread()
                                    }
                                }
                                .buttonStyle(.bordered)
                            }

                            if let status = model.planRunnerStatusMessage,
                               !status.isEmpty
                            {
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    SettingsSectionCard(
                        title: "Run State",
                        subtitle: runSubtitle
                    ) {
                        if model.planRunnerTaskStates.isEmpty {
                            Text("No plan tasks loaded yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(model.planRunnerTaskStates, id: \.taskID) { task in
                                    HStack(alignment: .top, spacing: 8) {
                                        statusBadge(task.status)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(task.taskID) · \(task.title)")
                                                .font(.caption.weight(.semibold))
                                            if !task.dependencyIDs.isEmpty {
                                                Text("Depends on: \(task.dependencyIDs.joined(separator: ", "))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(tokens.spacing.medium)
            }
            .navigationTitle("Plan Runner")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await model.loadLatestPlanRunForSelectedThread()
            }
        }
        .presentationDetents([.large])
    }

    private var runSubtitle: String {
        guard let run = model.activePlanRun else {
            return "No persisted plan run for this thread."
        }

        return "\(run.status.rawValue.capitalized) · \(run.completedTasks)/\(max(run.totalTasks, model.planRunnerTaskStates.count)) completed"
    }

    @ViewBuilder
    private func statusBadge(_ status: PlanTaskRunStatus) -> some View {
        let (text, tint): (String, Color) = switch status {
        case .pending:
            ("Pending", .secondary)
        case .running:
            ("Running", .blue)
        case .completed:
            ("Done", .green)
        case .failed:
            ("Failed", .red)
        case .skipped:
            ("Skipped", .orange)
        }

        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
