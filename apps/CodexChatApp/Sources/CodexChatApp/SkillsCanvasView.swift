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
        .background(SkillsModsTheme.canvasBackground(tokens: tokens))
        .navigationTitle("")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Skills")
                    .font(.title3.weight(.semibold))

                SkillsModsSearchField(text: $query, placeholder: "Search skills")

                Button {
                    model.refreshSkillsSurface()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    isInstallSkillSheetVisible = true
                } label: {
                    Label("Install", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedProjectID == nil)

                Spacer(minLength: 0)
            }

            Text("Installed skills")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SkillsModsTheme.pageHorizontalInset)
        .padding(.top, tokens.spacing.small)
        .padding(.bottom, tokens.spacing.xSmall)
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
            let visibleSkills = SkillsModsPresentation.filteredSkills(skills, query: query)
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
                                        .fill(SkillsModsTheme.cardBackground(tokens: tokens))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(SkillsModsTheme.subtleBorder(tokens: tokens))
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
                                .animation(
                                    .easeOut(duration: tokens.motion.transitionDuration).delay(Double(index) * 0.02),
                                    value: animateCards
                                )
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
}
