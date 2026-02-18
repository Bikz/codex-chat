import CodexChatUI
import SwiftUI

struct SkillsModsCanvasView: View {
    @ObservedObject var model: AppModel
    @Binding var isInstallSkillSheetVisible: Bool
    @Environment(\.designTokens) private var tokens

    enum Tab: String, CaseIterable {
        case skills = "Skills"
        case mods = "Mods"
    }

    @State private var selectedTab: Tab = .skills

    var body: some View {
        VStack(spacing: 0) {
            topSwitcher

            switch selectedTab {
            case .skills:
                SkillsCanvasView(model: model, isInstallSkillSheetVisible: $isInstallSkillSheetVisible)
                    .transition(.opacity)
            case .mods:
                ModsCanvas(model: model)
                    .transition(.opacity)
            }
        }
        .background(SkillsModsTheme.canvasBackground)
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
        .onChange(of: selectedTab) { _, newTab in
            switch newTab {
            case .skills:
                Task {
                    do { try await model.refreshSkills() } catch {}
                }
            case .mods:
                model.refreshModsSurface()
            }
        }
    }

    private var topSwitcher: some View {
        HStack {
            Picker("Section", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)
            Spacer()
        }
        .padding(.horizontal, tokens.spacing.medium)
        .padding(.top, tokens.spacing.small)
        .padding(.bottom, tokens.spacing.xSmall)
    }
}
