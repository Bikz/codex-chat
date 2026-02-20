import AppKit
import CodexChatCore
import CodexChatUI
import SwiftUI
import UniformTypeIdentifiers

struct ChatsCanvasView: View {
    @ObservedObject var model: AppModel
    @Binding var isInsertMemorySheetVisible: Bool
    @Environment(\.designTokens) private var tokens
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isComposerFocused: Bool
    @State private var isComposerDropTargeted = false
    @State private var permissionRecoveryDetailsNotice: AppModel.PermissionRecoveryNotice?

    var body: some View {
        VStack(spacing: 0) {
            if !model.isSelectedProjectTrusted, model.selectedProjectID != nil {
                ProjectTrustBanner(
                    onTrust: model.trustSelectedProject,
                    onSettings: model.showProjectSettings
                )
                .padding(.horizontal, tokens.spacing.medium)
                .padding(.top, tokens.spacing.small)
            }

            runtimeAwareConversationSurface

            VStack(alignment: .leading, spacing: 8) {
                FollowUpQueueView(model: model)
                if let request = model.pendingApprovalForSelectedThread {
                    InlineApprovalRequestView(model: model, request: request)
                } else {
                    composerSurface
                }

                if let notice = model.permissionRecoveryNotice {
                    permissionRecoveryInlineBanner(notice)
                        .padding(.horizontal, tokens.spacing.medium)
                }

                if let followUpStatus = model.followUpStatusMessage {
                    Text(followUpStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, tokens.spacing.medium)
                }
            }

            if model.isShellWorkspaceVisible {
                Divider()
                    .opacity(tokens.surfaces.hairlineOpacity)
                ShellWorkspaceDrawer(model: model)
                    .frame(height: 300)
                    .padding(.horizontal, tokens.spacing.medium)
                    .padding(.top, tokens.spacing.small)
                    .padding(.bottom, tokens.spacing.medium)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onAppear {
            Task {
                await model.refreshModsBarForSelectedThread()
            }
        }
        .onChange(of: model.selectedThreadID) { _, _ in
            Task {
                await model.refreshModsBarForSelectedThread()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    toggleSidebar()
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.leading")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Toggle sidebar")
                .help("Toggle sidebar")
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
        .toolbar(removing: .sidebarToggle)
        .sheet(item: $permissionRecoveryDetailsNotice) { notice in
            PermissionRecoveryDetailsSheet(
                notice: notice,
                onOpenSettings: {
                    model.openPermissionRecoverySettings(for: notice.target)
                }
            )
        }
    }

    private var composerSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.composerAttachments.isEmpty {
                composerContextStrip {
                    ForEach(model.composerAttachments) { attachment in
                        composerAttachmentChip(attachment)
                    }
                }
            } else if model.shouldShowComposerStarterPrompts {
                composerContextStrip {
                    ForEach(model.composerStarterPrompts, id: \.self) { prompt in
                        composerStarterPromptChip(prompt)
                    }
                }
            }

            HStack(alignment: .center, spacing: 10) {
                TextField(composerPlaceholder, text: $model.composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: tokens.typography.bodySize + 1, weight: .regular))
                    .lineLimit(1 ... 6)
                    .padding(.vertical, 10)
                    .frame(minHeight: 34)
                    .focused($isComposerFocused)
                    .onSubmit {
                        model.submitComposerWithQueuePolicy()
                    }
                    .accessibilityLabel("Message input")

                composerLeadingButton(
                    systemImage: "brain",
                    accessibilityLabel: "Insert memory snippet",
                    helpText: "Insert memory snippet",
                    isDisabled: model.selectedProjectID == nil
                ) {
                    isInsertMemorySheetVisible = true
                }

                composerLeadingButton(
                    systemImage: "paperclip",
                    accessibilityLabel: "Attach files or images",
                    helpText: "Attach files or images",
                    isDisabled: model.selectedProjectID == nil
                ) {
                    model.pickComposerAttachments()
                }

                Button {
                    // Defer state mutation until after the current AppKit layout cycle.
                    DispatchQueue.main.async {
                        model.toggleVoiceCapture()
                    }
                } label: {
                    Group {
                        if model.isVoiceCaptureRecording {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12, weight: .bold))
                        } else if case .transcribing = model.voiceCaptureState {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundStyle(voiceButtonForegroundColor)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(voiceButtonBackgroundColor)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("v", modifiers: [.option])
                .accessibilityLabel(voiceButtonAccessibilityLabel)
                .help("Toggle voice capture")
                .disabled(!model.canToggleVoiceCapture)

                Button {
                    model.submitComposerWithQueuePolicy()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(
                                    model.canSubmitComposerInput
                                        ? Color(hex: tokens.palette.accentHex).opacity(0.9)
                                        : Color(hex: tokens.palette.accentHex).opacity(0.28)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send message")
                .help("Send")
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canSubmitComposerInput)
            }

            if model.isComposerSkillAutocompleteActive {
                composerSkillAutocompleteList
            }

            if let voiceStatus = model.voiceCaptureStatusMessage {
                HStack(spacing: 6) {
                    switch model.voiceCaptureState {
                    case .recording:
                        Circle()
                            .fill(.red)
                            .frame(width: 7, height: 7)
                    case .transcribing:
                        ProgressView()
                            .controlSize(.small)
                    case .failed:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    case .idle, .requestingPermission:
                        EmptyView()
                    }

                    Text(voiceStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if case .recording = model.voiceCaptureState, let elapsed = model.voiceCaptureElapsedText {
                        Text(elapsed)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            ComposerControlBar(model: model)
        }
        .onExitCommand {
            guard model.isVoiceCaptureInProgress else { return }
            model.cancelVoiceCapture()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Color.primary.opacity(tokens.surfaces.baseOpacity * 0.95),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity * 0.95))

            if isComposerDropTargeted {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color(hex: tokens.palette.accentHex), lineWidth: 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(hex: tokens.palette.accentHex).opacity(0.08))
                    )
            }
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.16 : 0.06), radius: 10, y: 2)
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isComposerDropTargeted,
            perform: handleComposerFileDrop(providers:)
        )
        .padding(.horizontal, tokens.spacing.medium)
        .padding(.vertical, tokens.spacing.small)
    }

    private func permissionRecoveryInlineBanner(_ notice: AppModel.PermissionRecoveryNotice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(notice.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(notice.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button("Open Settings") {
                    model.openPermissionRecoverySettingsFromNotice()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Details") {
                    permissionRecoveryDetailsNotice = notice
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Dismiss") {
                    model.dismissPermissionRecoveryNotice()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.16 : 0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.45))
        )
    }

    private var voiceButtonForegroundColor: Color {
        if model.isVoiceCaptureRecording {
            return .white
        }
        if case .transcribing = model.voiceCaptureState {
            return Color(hex: tokens.palette.accentHex)
        }
        return composerLeadingButtonIconColor
    }

    private var voiceButtonBackgroundColor: Color {
        if model.isVoiceCaptureRecording {
            return .red.opacity(0.85)
        }
        if case .transcribing = model.voiceCaptureState {
            return Color(hex: tokens.palette.accentHex).opacity(0.12)
        }
        return .clear
    }

    private var voiceButtonAccessibilityLabel: String {
        switch model.voiceCaptureState {
        case .recording:
            "Stop voice capture"
        case .transcribing:
            "Transcribing voice input"
        case .requestingPermission:
            "Requesting voice capture permissions"
        case .idle, .failed:
            "Start voice capture"
        }
    }

    private var composerPlaceholder: String {
        if case .installCodex? = model.runtimeIssue {
            return "Install Codex CLI to enable runtime turns…"
        }
        if model.runtimeStatus == .starting {
            return "Connecting to Codex runtime…"
        }
        return model.composerInputPlaceholder
    }

    private func composerLeadingButton(
        systemImage: String,
        accessibilityLabel: String,
        helpText: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(composerLeadingButtonIconColor)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(helpText)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private func composerContextStrip(
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    content()
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
    }

    private func composerAttachmentChip(_ attachment: AppModel.ComposerAttachment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.kind == .localImage ? "photo" : "doc")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(attachment.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            Button {
                model.removeComposerAttachment(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(attachment.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(tokens.surfaces.baseOpacity))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity))
        )
        .help(attachment.path)
    }

    private func composerStarterPromptChip(_ starterPrompt: AppModel.ComposerStarterPrompt) -> some View {
        Button(starterPrompt.label) {
            model.insertStarterPrompt(starterPrompt.prompt)
            isComposerFocused = true
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(tokens.surfaces.baseOpacity))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity))
        )
    }

    @ViewBuilder
    private var composerSkillAutocompleteList: some View {
        let suggestions = model.composerSkillAutocompleteSuggestions

        VStack(alignment: .leading, spacing: 6) {
            Text("Skills")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if suggestions.isEmpty {
                Text("No matching skills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(suggestions) { item in
                            composerSkillSuggestionRow(item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(tokens.surfaces.baseOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity))
        )
    }

    private func composerSkillSuggestionRow(_ item: AppModel.SkillListItem) -> some View {
        Button {
            model.applyComposerSkillAutocompleteSuggestion(item)
            isComposerFocused = true
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("$\(item.skill.name)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(item.skill.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Insert skill \(item.skill.name)")
    }

    private func handleComposerFileDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else {
            return false
        }

        Task {
            let urls = await droppedFileURLs(from: providers)
            guard !urls.isEmpty else {
                return
            }

            await MainActor.run {
                guard model.selectedProjectID != nil else {
                    model.followUpStatusMessage = "Select a project before attaching files."
                    return
                }
                model.addComposerAttachments(urls)
            }
        }

        return true
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }

    private func droppedFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                  let url = await droppedFileURL(from: provider)
            else {
                continue
            }
            urls.append(url.standardizedFileURL)
        }
        return urls
    }

    private func droppedFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil)
                {
                    continuation.resume(returning: url)
                    return
                }

                if let text = item as? String {
                    if let url = URL(string: text), url.isFileURL {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(returning: URL(fileURLWithPath: text))
                    }
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private var composerLeadingButtonIconColor: Color {
        if colorScheme == .dark {
            return Color.primary.opacity(0.88)
        }
        return Color.primary.opacity(0.7)
    }

    @ViewBuilder
    private var runtimeAwareConversationSurface: some View {
        if case .installCodex? = model.runtimeIssue {
            InstallCodexGuidanceView()
        } else if let runtimeIssue = model.runtimeIssue {
            ErrorStateView(
                title: "Runtime unavailable",
                message: runtimeIssue.message,
                actionLabel: "Restart Runtime"
            ) {
                model.restartRuntime()
            }
        } else {
            switch model.conversationState {
            case .idle:
                conversationWithModsBar {
                    EmptyStateView(
                        title: "No active thread",
                        message: "Choose or create a thread to start chatting.",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                }
            case .loading:
                conversationWithModsBar {
                    LoadingStateView(title: "Preparing conversation…")
                }
            case let .failed(message):
                conversationWithModsBar {
                    ErrorStateView(title: "Conversation unavailable", message: message, actionLabel: "Retry") {
                        model.retryLoad()
                    }
                }
            case let .loaded(entries) where entries.isEmpty:
                conversationWithModsBar {
                    ThreadEmptyStateView()
                }
            case let .loaded(entries):
                conversationWithModsBar {
                    let presentationRows = model.presentationRowsForSelectedConversation(entries: entries)
                    let indexedRows = Array(presentationRows.enumerated())

                    ScrollViewReader { proxy in
                        List(indexedRows, id: \.element.id) { _, row in
                            switch row {
                            case let .message(message):
                                MessageRow(
                                    message: message,
                                    tokens: tokens,
                                    allowsExternalMarkdownContent: model.isSelectedProjectTrusted
                                )
                                .padding(.vertical, tokens.spacing.xSmall)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 0,
                                        leading: tokens.spacing.medium,
                                        bottom: 0,
                                        trailing: tokens.spacing.medium
                                    )
                                )
                            case let .action(card):
                                let workerTrace = model.workerTraceEntry(for: card)
                                Group {
                                    if model.transcriptDetailLevel == .detailed {
                                        ActionCardRow(
                                            card: card,
                                            onShowWorkerTrace: workerTrace == nil ? nil : {
                                                model.activeWorkerTraceEntry = workerTrace
                                            }
                                        )
                                    } else {
                                        InlineActionNoticeRow(
                                            model: model,
                                            card: card,
                                            onShowWorkerTrace: workerTrace == nil ? nil : {
                                                model.activeWorkerTraceEntry = workerTrace
                                            }
                                        )
                                    }
                                }
                                .padding(.vertical, tokens.spacing.xSmall)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 0,
                                        leading: tokens.spacing.medium,
                                        bottom: 0,
                                        trailing: tokens.spacing.medium
                                    )
                                )
                            case let .liveActivity(activity):
                                LiveTurnActivityRow(
                                    activity: activity,
                                    detailLevel: model.transcriptDetailLevel
                                )
                                .padding(.vertical, tokens.spacing.xSmall)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 0,
                                        leading: tokens.spacing.medium,
                                        bottom: 0,
                                        trailing: tokens.spacing.medium
                                    )
                                )
                            case let .turnSummary(summary):
                                TurnSummaryRow(
                                    summary: summary,
                                    detailLevel: model.transcriptDetailLevel,
                                    model: model
                                )
                                .padding(.vertical, tokens.spacing.xSmall)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 0,
                                        leading: tokens.spacing.medium,
                                        bottom: 0,
                                        trailing: tokens.spacing.medium
                                    )
                                )
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .onAppear {
                            scrollTranscriptToBottom(rows: presentationRows, proxy: proxy, animated: false)
                        }
                        .onChange(of: presentationRows.last?.id) { _, _ in
                            scrollTranscriptToBottom(rows: presentationRows, proxy: proxy, animated: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func conversationWithModsBar(
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        if model.canToggleModsBarForSelectedThread {
            HStack(spacing: 0) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.isModsBarVisibleForSelectedThread {
                    Divider()
                    ExtensionModsBarView(model: model)
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 440)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        } else {
            content()
        }
    }

    private func scrollTranscriptToBottom(
        rows: [TranscriptPresentationRow],
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let lastID = rows.last?.id else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: tokens.motion.transitionDuration)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct ThreadEmptyStateView: View {
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(tokens.surfaces.baseOpacity * 1.6))
                    .frame(width: 66, height: 66)
                CodexMonochromeMark()
                    .frame(width: 31, height: 31)
            }

            Text("Start a conversation")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct ComposerControlBar: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @State private var isCustomModelSheetVisible = false
    @State private var customModelDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                let selectedModelID = model.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
                Menu {
                    if model.runtimeDefaultModelID != nil {
                        Button {
                            model.setDefaultModel("")
                        } label: {
                            menuOptionLabel(
                                title: "Runtime default",
                                subtitle: model.runtimeDefaultModelID.map { model.modelDisplayName(for: $0) },
                                isSelected: model.isUsingRuntimeDefaultModel
                            )
                        }

                        if !model.featuredModelPresets.isEmpty || !model.overflowModelPresets.isEmpty {
                            Divider()
                        }
                    }

                    ForEach(model.featuredModelPresets, id: \.self) { preset in
                        Button {
                            model.setDefaultModel(preset)
                        } label: {
                            menuOptionLabel(
                                title: model.modelMenuLabel(for: preset),
                                isSelected: selectedModelID.caseInsensitiveCompare(
                                    preset.trimmingCharacters(in: .whitespacesAndNewlines)
                                ) == .orderedSame
                            )
                        }
                    }

                    if !model.overflowModelPresets.isEmpty {
                        Divider()

                        Menu("More…") {
                            ForEach(model.overflowModelPresets, id: \.self) { preset in
                                Button {
                                    model.setDefaultModel(preset)
                                } label: {
                                    menuOptionLabel(
                                        title: model.modelMenuLabel(for: preset),
                                        isSelected: selectedModelID.caseInsensitiveCompare(
                                            preset.trimmingCharacters(in: .whitespacesAndNewlines)
                                        ) == .orderedSame
                                    )
                                }
                            }
                        }
                    }

                    Divider()

                    Button("Custom…") {
                        customModelDraft = model.defaultModel
                        isCustomModelSheetVisible = true
                    }
                } label: {
                    controlChip(
                        value: model.defaultModelDisplayName,
                        systemImage: nil,
                        tint: Color.primary.opacity(0.78),
                        minWidth: 148
                    )
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Model")
                .accessibilityValue(model.defaultModelDisplayName)
                .help("Select model")

                if model.canChooseReasoningForSelectedModel {
                    Menu {
                        ForEach(model.reasoningPresets, id: \.self) { level in
                            Button {
                                model.setDefaultReasoning(level)
                            } label: {
                                menuOptionLabel(title: level.title, isSelected: level == model.defaultReasoning)
                            }
                        }
                    } label: {
                        controlChip(
                            value: model.defaultReasoning.title,
                            systemImage: nil,
                            tint: Color.primary.opacity(0.72),
                            minWidth: 118
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("Reasoning")
                    .accessibilityValue(model.defaultReasoning.title)
                    .help("Select reasoning effort")
                }

                if model.canChooseWebSearchForSelectedModel {
                    Menu {
                        ForEach(model.webSearchPresets, id: \.self) { mode in
                            Button {
                                model.setDefaultWebSearch(mode)
                            } label: {
                                menuOptionLabel(
                                    title: webSearchLabel(mode),
                                    subtitle: webSearchDescription(mode),
                                    isSelected: mode == model.defaultWebSearch
                                )
                            }
                        }
                    } label: {
                        controlChip(
                            value: webSearchLabel(model.defaultWebSearch),
                            systemImage: "globe",
                            tint: webSearchTint(model.defaultWebSearch),
                            minWidth: 94
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("Web search mode")
                    .help("Select web search mode")
                }

                Menu {
                    ForEach(AppModel.ComposerMemoryMode.allCases, id: \.self) { mode in
                        Button {
                            model.setComposerMemoryMode(mode)
                        } label: {
                            menuOptionLabel(
                                title: memoryModeLabel(mode),
                                subtitle: memoryModeDescription(mode),
                                isSelected: mode == model.composerMemoryMode
                            )
                        }
                    }
                } label: {
                    controlChip(
                        value: model.composerMemoryDisplayLabel,
                        systemImage: "brain",
                        tint: Color.primary.opacity(0.7),
                        minWidth: 108
                    )
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Memory mode")
                .help("Select memory behavior for this turn")

                Spacer()
            }
        }
        .sheet(isPresented: $isCustomModelSheetVisible) {
            CustomModelSheet(
                modelID: $customModelDraft,
                onCancel: {
                    isCustomModelSheetVisible = false
                },
                onSave: {
                    model.setDefaultModel(customModelDraft)
                    isCustomModelSheetVisible = false
                }
            )
        }
    }

    private func controlChip(
        value: String,
        systemImage: String?,
        tint: Color,
        minWidth: CGFloat
    ) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 14, height: 14)
                    .foregroundStyle(tint)
            }

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 2)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: minWidth, alignment: .leading)
        .background(
            Color.primary.opacity(tokens.surfaces.baseOpacity * 1.15),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity))
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func webSearchLabel(_ mode: ProjectWebSearchMode) -> String {
        switch mode {
        case .cached:
            "Standard"
        case .live:
            "Live web"
        case .disabled:
            "Web off"
        }
    }

    private func webSearchDescription(_ mode: ProjectWebSearchMode) -> String {
        switch mode {
        case .cached:
            "Uses cached web context."
        case .live:
            "Fetches fresh web results."
        case .disabled:
            "Disables web search."
        }
    }

    private func memoryModeLabel(_ mode: AppModel.ComposerMemoryMode) -> String {
        switch mode {
        case .projectDefault:
            "Auto"
        case .off:
            "Off"
        case .summariesOnly:
            "Summaries"
        case .summariesAndKeyFacts:
            "Summaries + facts"
        }
    }

    private func memoryModeDescription(_ mode: AppModel.ComposerMemoryMode) -> String? {
        switch mode {
        case .projectDefault:
            "Uses the project default memory setting."
        case .off:
            "Skips memory writes for this turn."
        case .summariesOnly:
            "Writes summary memory only."
        case .summariesAndKeyFacts:
            "Writes summaries and key facts."
        }
    }

    private func menuOptionLabel(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark" : "circle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(
                    isSelected
                        ? Color(hex: tokens.palette.accentHex)
                        : Color.secondary.opacity(0.45)
                )
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func webSearchTint(_ mode: ProjectWebSearchMode) -> Color {
        switch mode {
        case .cached:
            .secondary
        case .live:
            Color(hex: tokens.palette.accentHex)
        case .disabled:
            .orange
        }
    }
}

private struct CustomModelSheet: View {
    @Binding var modelID: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Model")
                .font(.title3.weight(.semibold))

            TextField("Model ID", text: $modelID)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}

private struct PermissionRecoveryDetailsSheet: View {
    let notice: AppModel.PermissionRecoveryNotice
    let onOpenSettings: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(notice.message)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    Divider()

                    Text("How to fix")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(notice.remediationSteps.enumerated()), id: \.offset) { index, step in
                            Text("\(index + 1). \(step)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(notice.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open Settings") {
                        onOpenSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
