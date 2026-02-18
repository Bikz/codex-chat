import CodexChatUI
import SwiftUI

struct SkillsCanvasView: View {
    @ObservedObject var model: AppModel
    @Binding var isInstallSkillSheetVisible: Bool
    @Environment(\.designTokens) private var tokens

    @State private var query = ""
    @State private var animateCards = false

    private let cardColumns = [
        GridItem(.flexible(minimum: 240), spacing: 12, alignment: .top),
        GridItem(.flexible(minimum: 240), spacing: 12, alignment: .top),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            skillsSurface
        }
        .background(SkillsModsTheme.canvasBackground)
        .navigationTitle("")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skills")
                        .font(.system(size: 48, weight: .semibold, design: .rounded))

                    Text("Give Codex superpowers.")
                        .font(.title3.weight(.regular))
                        .foregroundStyle(SkillsModsTheme.mutedText)
                }

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    Button {
                        model.refreshSkillsSurface()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    SkillsModsSearchField(text: $query, placeholder: "Search skills")

                    Button {
                        isInstallSkillSheetVisible = true
                    } label: {
                        Label("New skill", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedProjectID == nil)
                }
            }

            Text("Installed")
                .font(.title3.weight(.semibold))
        }
        .padding(.horizontal, SkillsModsTheme.pageHorizontalInset)
        .padding(.top, SkillsModsTheme.pageVerticalInset)
        .padding(.bottom, 14)
        .background(SkillsModsTheme.headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SkillsModsTheme.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var skillsSurface: some View {
        switch model.skillsState {
        case .idle, .loading:
            LoadingStateView(title: "Scanning installed skills…")
                .padding(SkillsModsTheme.pageHorizontalInset)
        case let .failed(message):
            ErrorStateView(title: "Couldn’t load skills", message: message, actionLabel: "Retry") {
                model.refreshSkillsSurface()
            }
            .padding(SkillsModsTheme.pageHorizontalInset)
        case let .loaded(skills) where skills.isEmpty:
            EmptyStateView(
                title: "No skills discovered",
                message: "Install a skill from git or npx, then enable it for this project.",
                systemImage: "square.stack.3d.up"
            )
            .padding(SkillsModsTheme.pageHorizontalInset)
        case let .loaded(skills):
            let visibleSkills = filteredSkills(from: skills)
            if visibleSkills.isEmpty {
                EmptyStateView(
                    title: "No matching skills",
                    message: "Try a different search term.",
                    systemImage: "magnifyingglass"
                )
                .padding(SkillsModsTheme.pageHorizontalInset)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: tokens.spacing.small) {
                        if let skillStatusMessage = model.skillStatusMessage {
                            Text(skillStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.65))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(SkillsModsTheme.subtleBorder)
                                )
                        }

                        LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 12) {
                            ForEach(Array(visibleSkills.enumerated()), id: \.element.id) { index, item in
                                SkillRow(
                                    item: item,
                                    hasSelectedProject: model.selectedProjectID != nil,
                                    onToggle: { enabled in
                                        model.setSkillEnabled(item, enabled: enabled)
                                    },
                                    onInsert: {
                                        model.selectSkillForComposer(item)
                                        model.detailDestination = .thread
                                    },
                                    onUpdate: {
                                        model.updateSkill(item)
                                    }
                                )
                                .opacity(animateCards ? 1 : 0)
                                .offset(y: animateCards ? 0 : 8)
                                .animation(.easeOut(duration: 0.24).delay(Double(index) * 0.02), value: animateCards)
                            }
                        }
                    }
                    .padding(.horizontal, SkillsModsTheme.pageHorizontalInset)
                    .padding(.top, 16)
                    .padding(.bottom, tokens.spacing.large)
                }
                .onAppear {
                    animateCards = true
                }
            }
        }
    }

    private func filteredSkills(from skills: [AppModel.SkillListItem]) -> [AppModel.SkillListItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return skills }

        return skills.filter { item in
            item.skill.name.localizedCaseInsensitiveContains(trimmed)
                || item.skill.description.localizedCaseInsensitiveContains(trimmed)
                || item.skill.scope.rawValue.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
