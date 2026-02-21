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
            if !model.isOnboardingActive {
                ToolbarItem(placement: .navigation) {
                    Button {
                        toggleSidebarVisibility()
                    } label: {
                        Label("Toggle Sidebar", systemImage: "sidebar.left")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Toggle sidebar")
                    .help("Toggle sidebar")
                    .keyboardShortcut("s", modifiers: [.command, .option])
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.openReviewChanges()
                    } label: {
                        Label("Review Changes", systemImage: "doc.text.magnifyingglass")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Review pending changes")
                    .help("Review changes")
                    .disabled(!model.canReviewChanges)

                    Button {
                        model.revealSelectedThreadArchiveInFinder()
                    } label: {
                        Label("Reveal Chat File", systemImage: "doc.text")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Reveal thread transcript file in Finder")
                    .help("Reveal thread transcript file")
                    .disabled(model.selectedThreadID == nil)

                    Button {
                        model.toggleShellWorkspace()
                    } label: {
                        Label("Shell Workspace", systemImage: "terminal")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Toggle shell workspace")
                    .help("Toggle shell workspace")

                    Button {
                        model.openPlanRunnerSheet()
                    } label: {
                        Label("Plan Runner", systemImage: "list.number")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Open plan runner")
                    .help("Open plan runner")
                    .disabled(model.selectedThreadID == nil || model.selectedProjectID == nil)

                    if model.canToggleModsBarForSelectedThread {
                        Button {
                            model.toggleModsBar()
                        } label: {
                            Label("Mods bar", systemImage: "sidebar.right")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityLabel("Toggle mods bar")
                        .help(
                            SkillsModsPresentation.modsBarHelpText(
                                hasActiveModsBarSource: model.isModsBarAvailableForSelectedThread
                            )
                        )
                    }
                }
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

    private func toggleSidebarVisibility() {
        withAnimation(.easeInOut(duration: tokens.motion.transitionDuration)) {
            splitViewVisibility = Self.nextSplitViewVisibility(
                current: splitViewVisibility,
                isOnboardingActive: model.isOnboardingActive
            )
        }
    }

    static func nextSplitViewVisibility(
        current: NavigationSplitViewVisibility,
        isOnboardingActive: Bool
    ) -> NavigationSplitViewVisibility {
        guard !isOnboardingActive else {
            return .detailOnly
        }
        return current == .detailOnly ? .all : .detailOnly
    }

    private var unscopedApprovalSheetBinding: Binding<RuntimeApprovalRequest?> {
        Binding(
            get: { model.unscopedApprovalRequests.first },
            set: { _ in }
        )
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
