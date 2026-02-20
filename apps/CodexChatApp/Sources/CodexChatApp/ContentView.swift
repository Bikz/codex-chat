import CodexChatUI
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @State private var isInstallSkillSheetVisible = false
    @State private var isInsertMemorySheetVisible = false
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
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
        .sheet(isPresented: $model.isNewProjectSheetVisible) {
            NewProjectSheet(model: model)
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
            model.unscopedApprovalRequest
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
        .sheet(item: Binding(get: {
            model.pendingComputerActionPreview
        }, set: { _ in })) { preview in
            ComputerActionPreviewSheet(model: model, preview: preview)
                .interactiveDismissDisabled(model.isComputerActionExecutionInProgress)
        }
        .sheet(item: Binding(get: {
            model.activeWorkerTraceEntry
        }, set: { _ in
            model.dismissWorkerTraceSheet()
        })) { entry in
            WorkerTraceDetailsSheet(model: model, entry: entry)
        }
        .sheet(isPresented: $model.isPlanRunnerSheetVisible) {
            PlanRunnerSheet(model: model)
        }
        .onAppear {
            model.onAppear()
            syncSplitViewVisibility(isOnboardingActive: model.isOnboardingActive)
        }
        .onChange(of: model.detailDestination) { _, newValue in
            switch newValue {
            case .skillsAndMods:
                model.refreshModsSurface()
            case .thread, .none:
                break
            }
        }
        .onChange(of: model.isOnboardingActive) { _, isOnboardingActive in
            syncSplitViewVisibility(isOnboardingActive: isOnboardingActive)
        }
    }

    @ViewBuilder
    private var detailSurface: some View {
        if model.isOnboardingActive {
            OnboardingView(model: model)
        } else {
            switch model.detailDestination {
            case .thread:
                ChatsCanvasView(model: model, isInsertMemorySheetVisible: $isInsertMemorySheetVisible)
            case .skillsAndMods:
                SkillsModsCanvasView(model: model, isInstallSkillSheetVisible: $isInstallSkillSheetVisible)
            case .none:
                ChatsCanvasView(model: model, isInsertMemorySheetVisible: $isInsertMemorySheetVisible)
            }
        }
    }

    private func syncSplitViewVisibility(isOnboardingActive: Bool) {
        splitViewVisibility = isOnboardingActive ? .detailOnly : .all
    }
}
