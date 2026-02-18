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
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
        } detail: {
            detailSurface
                .background(Color(hex: tokens.palette.backgroundHex))
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationTitle("")
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
        .sheet(item: Binding(get: {
            model.activeUntrustedShellWarning
        }, set: { _ in })) { warning in
            UntrustedShellWarningSheet(
                context: warning,
                onCancel: model.dismissUntrustedShellWarning,
                onContinue: model.confirmUntrustedShellWarning
            )
        }
        .onAppear {
            model.onAppear()
        }
        .onChange(of: model.detailDestination) { newValue in
            switch newValue {
            case .skillsAndMods:
                model.refreshModsSurface()
            case .thread, .none:
                break
            }
        }
    }

    @ViewBuilder
    private var detailSurface: some View {
        switch model.detailDestination {
        case .thread:
            ChatsCanvasView(model: model, isInsertMemorySheetVisible: $isInsertMemorySheetVisible)
        case .skillsAndMods:
            SkillsModsCanvasView(model: model, isInstallSkillSheetVisible: $isInstallSkillSheetVisible)
        case .none:
            ChatSetupView(model: model)
        }
    }
}
