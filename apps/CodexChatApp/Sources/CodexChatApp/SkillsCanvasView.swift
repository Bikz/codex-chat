import CodexChatUI
import SwiftUI

struct SkillsCanvasView: View {
    @ObservedObject var model: AppModel
    @Binding var isInstallSkillSheetVisible: Bool
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Skills")
                    .font(.system(size: tokens.typography.titleSize, weight: .semibold))
                Spacer()

                Button("Refresh") {
                    model.refreshSkillsSurface()
                }
                .buttonStyle(.bordered)

                Button("Install Skill…") {
                    isInstallSkillSheetVisible = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedProjectID == nil)
            }
            .padding(tokens.spacing.medium)

            if let skillStatusMessage = model.skillStatusMessage {
                Text(skillStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, tokens.spacing.medium)
            }

            skillsSurface
                .padding(tokens.spacing.medium)

            Spacer(minLength: 0)
        }
        .navigationTitle("Skills")
    }

    @ViewBuilder
    private var skillsSurface: some View {
        switch model.skillsState {
        case .idle, .loading:
            LoadingStateView(title: "Scanning installed skills…")
        case let .failed(message):
            ErrorStateView(title: "Couldn’t load skills", message: message, actionLabel: "Retry") {
                model.refreshSkillsSurface()
            }
        case let .loaded(skills) where skills.isEmpty:
            EmptyStateView(
                title: "No skills discovered",
                message: "Install a skill from git or npx, then enable it for this project.",
                systemImage: "square.stack.3d.up"
            )
        case let .loaded(skills):
            List(skills) { item in
                SkillRow(
                    item: item,
                    hasSelectedProject: model.selectedProjectID != nil,
                    onToggle: { enabled in
                        model.setSkillEnabled(item, enabled: enabled)
                    },
                    onInsert: {
                        model.selectSkillForComposer(item)
                        model.navigationSection = .chats
                    },
                    onUpdate: {
                        model.updateSkill(item)
                    }
                )
            }
            .listStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: tokens.radius.medium))
        }
    }
}
