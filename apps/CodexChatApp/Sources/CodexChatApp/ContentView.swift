import AppKit
import CodexChatUI
import CodexKit
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
                .background(detailBackground)
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    toggleSidebar()
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.leading")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Toggle sidebar")
                .help("Toggle sidebar")
            }
        }
        .toolbar(removing: .sidebarToggle)
        .navigationTitle("")
        .sheet(isPresented: $model.isDiagnosticsVisible) {
            DiagnosticsView(
                runtimeStatus: model.runtimeStatus,
                runtimePoolSnapshot: model.runtimePoolSnapshot,
                adaptiveTurnConcurrencyLimit: model.adaptiveTurnConcurrencyLimit,
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
        .sheet(item: unscopedApprovalSheetBinding) { request in
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

    private var unscopedApprovalSheetBinding: Binding<RuntimeApprovalRequest?> {
        Binding(
            get: { model.unscopedApprovalRequests.first },
            set: { _ in }
        )
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }

    @ViewBuilder
    private var detailBackground: some View {
        let isCustomThemeEnabled = model.userThemeCustomization.isEnabled
        let chatHex = isCustomThemeEnabled
            ? (model.userThemeCustomization.backgroundHex ?? tokens.palette.backgroundHex)
            : tokens.palette.backgroundHex
        if isCustomThemeEnabled {
            ZStack {
                Color(hex: chatHex)
                    .opacity(model.isTransparentThemeMode ? 0.58 : 1)
                if let gradientHex = model.userThemeCustomization.chatGradientHex,
                   model.userThemeCustomization.gradientStrength > 0
                {
                    LinearGradient(
                        colors: [Color(hex: chatHex), Color(hex: gradientHex)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(model.userThemeCustomization.gradientStrength)
                }
            }
        } else {
            Color(hex: chatHex)
        }
    }
}
