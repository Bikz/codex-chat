import CodexChatUI
import CodexKit
import SwiftUI

struct ContentView: View {
    enum ToolbarIcon: String, CaseIterable {
        case pendingApprovals = "exclamationmark.bubble"
        case reviewChanges = "doc.text.magnifyingglass"
        case revealChatFile = "doc.text"
        case shellWorkspace = "terminal"
        case planRunner = "list.number"
        case modsBar = "sidebar.right"
    }

    static let splitBackgroundExtensionEdges: Edge.Set = .top
    static let usesCustomSidebarToolbarButton = false

    static func primaryToolbarSystemImages(canToggleModsBar: Bool) -> [String] {
        var images = [
            ToolbarIcon.pendingApprovals.rawValue,
            ToolbarIcon.reviewChanges.rawValue,
            ToolbarIcon.revealChatFile.rawValue,
            ToolbarIcon.shellWorkspace.rawValue,
            ToolbarIcon.planRunner.rawValue,
        ]
        if canToggleModsBar {
            images.append(ToolbarIcon.modsBar.rawValue)
        }
        return images
    }

    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @Environment(\.colorScheme) private var colorScheme
    @State private var isInstallSkillSheetVisible = false
    @State private var isInsertMemorySheetVisible = false
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
        } detail: {
            detailSurface
                .background(
                    detailBackground
                        .ignoresSafeArea(.container, edges: Self.splitBackgroundExtensionEdges)
                )
        }
        .background(
            detailBackground
                .ignoresSafeArea(.container, edges: Self.splitBackgroundExtensionEdges)
        )
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            if !model.isOnboardingActive {
                ToolbarItemGroup(placement: .primaryAction) {
                    if model.totalPendingApprovalCount > 0 {
                        Button {
                            model.openApprovalInbox()
                        } label: {
                            Label("Pending approvals", systemImage: ToolbarIcon.pendingApprovals.rawValue)
                                .labelStyle(.iconOnly)
                        }
                        .overlay(alignment: .topTrailing) {
                            Text("\(model.totalPendingApprovalCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(.red.opacity(0.95))
                                )
                                .offset(x: 6, y: -6)
                        }
                        .accessibilityLabel("Open pending approvals")
                        .help("Pending approvals")
                    }

                    Button {
                        model.openReviewChanges()
                    } label: {
                        Label("Review Changes", systemImage: ToolbarIcon.reviewChanges.rawValue)
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Review pending changes")
                    .help("Review changes")
                    .disabled(!model.canReviewChanges)

                    Button {
                        model.revealSelectedThreadArchiveInFinder()
                    } label: {
                        Label("Reveal Chat File", systemImage: ToolbarIcon.revealChatFile.rawValue)
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Reveal thread transcript file in Finder")
                    .help("Reveal thread transcript file")
                    .disabled(model.selectedThreadID == nil)

                    Button {
                        model.toggleShellWorkspace()
                    } label: {
                        Label("Shell Workspace", systemImage: ToolbarIcon.shellWorkspace.rawValue)
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Toggle shell workspace")
                    .help("Toggle shell workspace")

                    Button {
                        model.openPlanRunnerSheet()
                    } label: {
                        Label("Plan Runner", systemImage: ToolbarIcon.planRunner.rawValue)
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Open plan runner")
                    .help("Open plan runner")
                    .disabled(model.selectedThreadID == nil || model.selectedProjectID == nil)

                    if model.canToggleModsBarForSelectedThread {
                        Button {
                            model.toggleModsBar()
                        } label: {
                            Label("Mods bar", systemImage: ToolbarIcon.modsBar.rawValue)
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
        .navigationTitle("")
        .sheet(isPresented: $model.isDiagnosticsVisible) {
            DiagnosticsView(
                runtimeStatus: model.runtimeStatus,
                runtimePoolSnapshot: model.runtimePoolSnapshot,
                adaptiveTurnConcurrencyLimit: model.adaptiveTurnConcurrencyLimit,
                logs: model.logs,
                extensibilityDiagnostics: model.extensibilityDiagnostics,
                selectedProjectID: model.selectedProjectID,
                selectedThreadID: model.selectedThreadID,
                projectLabelsByID: Dictionary(
                    uniqueKeysWithValues: model.projects.map { ($0.id, $0.name) }
                ),
                threadLabelsByID: Dictionary(
                    model.threads
                        .map { ($0.id, $0.title) } + model.generalThreads.map { ($0.id, $0.title) },
                    uniquingKeysWith: { first, _ in first }
                ),
                automationTimelineFocusFilter: model.automationTimelineFocusFilter,
                onAutomationTimelineFocusFilterChange: model.setAutomationTimelineFocusFilter,
                onFocusTimelineProject: model.focusAutomationTimelineProject,
                onFocusTimelineThread: model.focusAutomationTimelineThread,
                canExecuteRerunCommand: model.isExtensibilityRerunCommandAllowlisted,
                rerunExecutionPolicyMessage: model.extensibilityRerunCommandPolicyMessage,
                onExecuteRerunCommand: model.executeAllowlistedExtensibilityRerunCommand,
                onPrepareRerunCommand: model.prepareExtensibilityRerunCommand,
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
        .sheet(isPresented: $model.isApprovalInboxVisible) {
            PendingApprovalsInboxSheet(model: model)
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
            VStack(spacing: 0) {
                if model.totalPendingApprovalCount > 0 {
                    pendingApprovalsBanner
                        .padding(.horizontal, tokens.spacing.medium)
                        .padding(.top, tokens.spacing.small)
                }

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
        let appearance: AppModel.UserThemeCustomization.Appearance = colorScheme == .dark ? .dark : .light
        let resolved = model.userThemeCustomization.resolvedColors(for: appearance)
        let isCustomThemeEnabled = model.userThemeCustomization.isEnabled
        let chatHex = isCustomThemeEnabled
            ? (resolved.backgroundHex ?? tokens.palette.backgroundHex)
            : tokens.palette.backgroundHex
        if isCustomThemeEnabled {
            ZStack {
                Color(hex: chatHex)
                    .opacity(model.isTransparentThemeMode ? 0.58 : 1)
                if let gradientHex = resolved.chatGradientHex,
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

    private var pendingApprovalsBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.bubble.fill")
                .foregroundStyle(.orange)

            Text(model.totalPendingApprovalCount == 1 ? "1 pending approval needs attention." : "\(model.totalPendingApprovalCount) pending approvals need attention.")
                .font(.caption.weight(.semibold))

            Spacer(minLength: 0)

            Button("Open Inbox") {
                model.openApprovalInbox()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.16 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.45))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pending approvals banner")
    }
}
