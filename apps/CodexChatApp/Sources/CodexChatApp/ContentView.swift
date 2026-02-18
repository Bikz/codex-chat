import CodexChatUI
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @State private var isInstallSkillSheetVisible = false
    @State private var isInsertMemorySheetVisible = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            detailSurface
        }
        .background(Color(hex: tokens.palette.backgroundHex))
        .sheet(isPresented: $model.isDiagnosticsVisible) {
            DiagnosticsView(
                runtimeStatus: model.runtimeStatus,
                logs: model.logs,
                onClose: model.closeDiagnostics
            )
        }
        .sheet(isPresented: $model.isAPIKeyPromptVisible) {
            APIKeyLoginSheet(model: model)
        }
        .sheet(isPresented: $model.isProjectSettingsVisible) {
            ProjectSettingsSheet(model: model)
        }
        .sheet(isPresented: $model.isReviewChangesVisible) {
            ReviewChangesSheet(model: model)
        }
        .sheet(isPresented: $isInstallSkillSheetVisible) {
            InstallSkillSheet(model: model, isPresented: $isInstallSkillSheetVisible)
        }
        .sheet(isPresented: $isInsertMemorySheetVisible) {
            MemorySnippetInsertSheet(model: model, isPresented: $isInsertMemorySheetVisible)
        }
        .sheet(item: Binding(get: {
            model.pendingModReview
        }, set: { _ in })) { review in
            ModChangesReviewSheet(model: model, review: review)
                .interactiveDismissDisabled(true)
        }
        .sheet(item: Binding(get: {
            model.activeApprovalRequest
        }, set: { _ in })) { request in
            ApprovalRequestSheet(model: model, request: request)
                .interactiveDismissDisabled(model.isApprovalDecisionInProgress)
        }
        .onAppear {
            model.onAppear()
        }
        .onChange(of: model.navigationSection) { newValue in
            switch newValue {
            case .skills:
                model.refreshSkillsSurface()
            case .mods:
                model.refreshModsSurface()
            case .chats, .memory:
                break
            }
        }
    }

    @ViewBuilder
    private var detailSurface: some View {
        switch model.navigationSection {
        case .chats:
            ChatsCanvasView(model: model, isInsertMemorySheetVisible: $isInsertMemorySheetVisible)
        case .skills:
            SkillsCanvasView(model: model, isInstallSkillSheetVisible: $isInstallSkillSheetVisible)
        case .memory:
            MemoryCanvas(model: model)
        case .mods:
            ModsCanvas(model: model)
        }
    }
}
