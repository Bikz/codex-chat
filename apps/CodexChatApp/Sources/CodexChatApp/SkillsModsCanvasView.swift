import CodexChatUI
import SwiftUI

struct SkillsModsCanvasView: View {
    @ObservedObject var model: AppModel
    @Binding var isInstallSkillSheetVisible: Bool

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
        .onChange(of: selectedTab) { newTab in
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
            Spacer()
            Picker("Section", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 190)
            Spacer()
        }
        .padding(.vertical, 16)
        .background(SkillsModsTheme.headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SkillsModsTheme.border)
                .frame(height: 1)
        }
    }
}
