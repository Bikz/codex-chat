import AppKit
import CodexChatCore
import CodexChatUI
import SwiftUI

struct SettingsView: View {
    static let minimumWindowSize = CGSize(width: 940, height: 620)
    static let detailMaxContentWidth: CGFloat = 980
    static let themePresetGridColumnCount = 5

    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AccountDisplayNamePreference.key) private var preferredAccountDisplayName = ""

    @State private var selectedSection: SettingsSection = .defaultSelection

    @State private var runtimeModelDraft = ""
    @State private var safetySandboxMode: ProjectSandboxMode = .readOnly
    @State private var safetyApprovalPolicy: ProjectApprovalPolicy = .untrusted
    @State private var safetyNetworkAccess = false
    @State private var safetyWebSearchMode: ProjectWebSearchMode = .cached
    @State private var pendingSafetyDefaults: ProjectSafetySettings?
    @State private var isSafetyApplyPromptVisible = false

    @State private var generalSandboxMode: ProjectSandboxMode = .readOnly
    @State private var generalApprovalPolicy: ProjectApprovalPolicy = .untrusted
    @State private var generalNetworkAccess = false
    @State private var generalWebSearchMode: ProjectWebSearchMode = .cached
    @State private var generalMemoryWriteMode: ProjectMemoryWriteMode = .off
    @State private var generalMemoryEmbeddingsEnabled = false
    @State private var isSyncingGeneralProject = false
    @State private var pendingGeneralSafetySettings: ProjectSafetySettings?
    @State private var isGeneralDangerConfirmationVisible = false
    @State private var generalDangerConfirmationInput = ""
    @State private var generalDangerConfirmationError: String?
    @State private var isRuntimeConfigExpanded = false
    @State private var lastSyncedGeneralProject: ProjectRecord?
    @State private var isAdvancedModsUnlockConfirmationVisible = false
    @State private var advancedModsUnlockInput = ""
    @State private var advancedModsUnlockError: String?
    @State private var isThemeCustomEditorExpanded = false
    @State private var customThemeEditorAppearance: AppModel.UserThemeCustomization.Appearance = .dark
    @State private var customThemeNameDraft = "My Theme"

    var body: some View {
        NavigationSplitView {
            sidebar
                .padding(tokens.spacing.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    settingsSidebarBackground
                        .ignoresSafeArea(.container, edges: SettingsLiquidGlassStyle.safeAreaExtensionEdges)
                )
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: tokens.spacing.medium) {
                    SettingsHeroHeader(
                        eyebrow: "Settings",
                        title: selectedSection.title,
                        subtitle: selectedSection.subtitle,
                        symbolName: selectedSection.symbolName
                    )
                    sectionContent
                }
                .frame(maxWidth: Self.detailMaxContentWidth, alignment: .leading)
                .padding(tokens.spacing.medium)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(
                settingsDetailBackground
                    .ignoresSafeArea(.container, edges: SettingsLiquidGlassStyle.safeAreaExtensionEdges)
            )
        }
        .background(
            settingsDetailBackground
                .ignoresSafeArea(.container, edges: SettingsLiquidGlassStyle.safeAreaExtensionEdges)
        )
        .navigationSplitViewStyle(.balanced)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationTitle("")
        .tint(Color(hex: tokens.palette.accentHex))
        .frame(
            minWidth: Self.minimumWindowSize.width,
            minHeight: Self.minimumWindowSize.height
        )
        .animation(.easeInOut(duration: tokens.motion.transitionDuration), value: selectedSection)
        .onAppear {
            runtimeModelDraft = model.isUsingRuntimeDefaultModel ? "" : model.defaultModel
            syncSafetyDefaultsFromModel()
            syncGeneralProjectFromModel(force: true)
            syncThemeDraftFromModel()
            customThemeEditorAppearance = colorScheme == .dark ? .dark : .light
        }
        .onChange(of: model.defaultSafetySettings) { _, _ in
            syncSafetyDefaultsFromModel()
        }
        .onChange(of: model.defaultModel) { _, newValue in
            runtimeModelDraft = model.isUsingRuntimeDefaultModel ? "" : newValue
        }
        .onChange(of: selectedSection) { _, newValue in
            if newValue == .generalProject {
                syncGeneralProjectFromModel(force: true)
            } else if newValue != .runtime {
                isRuntimeConfigExpanded = false
            }
        }
        .onReceive(model.$projectsState) { _ in
            guard selectedSection == .generalProject else {
                return
            }
            syncGeneralProjectFromModel()
        }
        .onChange(of: model.savedCustomThemePreset) { _, _ in
            syncThemeDraftFromModel()
        }
        .confirmationDialog(
            "Apply global safety defaults",
            isPresented: $isSafetyApplyPromptVisible,
            titleVisibility: .visible
        ) {
            Button("Apply to New Projects Only") {
                guard let pendingSafetyDefaults else { return }
                model.saveGlobalSafetyDefaults(pendingSafetyDefaults, applyToExistingProjects: false)
            }

            Button("Apply to Existing + New Projects") {
                guard let pendingSafetyDefaults else { return }
                model.saveGlobalSafetyDefaults(pendingSafetyDefaults, applyToExistingProjects: true)
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose whether these defaults should affect only newly created projects or also update existing projects.")
        }
        .sheet(isPresented: $isGeneralDangerConfirmationVisible) {
            DangerConfirmationSheet(
                phrase: model.dangerConfirmationPhrase,
                subtitle: "Type the confirmation phrase to enable dangerous General project settings.",
                input: $generalDangerConfirmationInput,
                errorText: generalDangerConfirmationError,
                onCancel: {
                    generalDangerConfirmationInput = ""
                    generalDangerConfirmationError = nil
                    pendingGeneralSafetySettings = nil
                    isGeneralDangerConfirmationVisible = false
                },
                onConfirm: {
                    guard DangerConfirmationSheet.isPhraseMatch(
                        input: generalDangerConfirmationInput,
                        phrase: model.dangerConfirmationPhrase
                    ) else {
                        generalDangerConfirmationError = "Phrase did not match."
                        return
                    }
                    if let pendingGeneralSafetySettings {
                        model.updateGeneralProjectSafetySettings(
                            sandboxMode: pendingGeneralSafetySettings.sandboxMode,
                            approvalPolicy: pendingGeneralSafetySettings.approvalPolicy,
                            networkAccess: pendingGeneralSafetySettings.networkAccess,
                            webSearch: pendingGeneralSafetySettings.webSearch
                        )
                    }
                    generalDangerConfirmationInput = ""
                    generalDangerConfirmationError = nil
                    pendingGeneralSafetySettings = nil
                    isGeneralDangerConfirmationVisible = false
                }
            )
        }
        .sheet(isPresented: $isAdvancedModsUnlockConfirmationVisible) {
            DangerConfirmationSheet(
                phrase: model.dangerConfirmationPhrase,
                subtitle: "Type the confirmation phrase to unlock advanced executable mods.",
                input: $advancedModsUnlockInput,
                errorText: advancedModsUnlockError,
                onCancel: {
                    advancedModsUnlockInput = ""
                    advancedModsUnlockError = nil
                    isAdvancedModsUnlockConfirmationVisible = false
                },
                onConfirm: {
                    guard DangerConfirmationSheet.isPhraseMatch(
                        input: advancedModsUnlockInput,
                        phrase: model.dangerConfirmationPhrase
                    ) else {
                        advancedModsUnlockError = "Phrase did not match."
                        return
                    }
                    model.setAdvancedExecutableModsUnlocked(true)
                    advancedModsUnlockInput = ""
                    advancedModsUnlockError = nil
                    isAdvancedModsUnlockConfirmationVisible = false
                }
            )
        }
    }

    private var sidebar: some View {
        let style = SettingsLiquidGlassStyle.sidebarContainerStyle(glassEnabled: model.isTransparentThemeMode)

        return VStack(alignment: .leading, spacing: tokens.spacing.small) {
            SettingsInlineHeader(
                eyebrow: "Workspace",
                title: "Preferences",
                subtitle: "Tune behavior, safety, and storage.",
                symbolName: "slider.horizontal.3"
            )
            .padding(.horizontal, 2)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    SettingsSidebarItem(
                        title: section.title,
                        symbolName: section.symbolName,
                        isSelected: selectedSection == section
                    ) {
                        selectedSection = section
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(2)
        }
        .padding(tokens.spacing.small)
        .tokenCard(
            style: .panel,
            radius: tokens.radius.large,
            strokeOpacity: style.strokeOpacity,
            shadowRadius: style.shadowRadius
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .account:
            accountCard
        case .appearance:
            appearanceCard
        case .runtime:
            runtimeContent
        case .generalProject:
            generalProjectContent
        case .safetyDefaults:
            safetyDefaultsCard
        case .experimental:
            experimentalCard
        case .diagnostics:
            diagnosticsCard
        case .storage:
            storageCard
        }
    }

    private var runtimeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            runtimeDefaultsCard
            runtimeConfigCard
        }
    }

    private var settingsSidebarBackground: some View {
        let appearance: AppModel.UserThemeCustomization.Appearance = colorScheme == .dark ? .dark : .light
        let resolved = model.userThemeCustomization.resolvedColors(for: appearance)
        let isCustomThemeEnabled = model.userThemeCustomization.isEnabled
        return themedBackground(
            baseHex: isCustomThemeEnabled
                ? (resolved.sidebarHex ?? tokens.palette.sidebarHex)
                : tokens.palette.sidebarHex,
            gradientHex: isCustomThemeEnabled ? resolved.sidebarGradientHex : nil
        )
    }

    private var settingsDetailBackground: some View {
        let appearance: AppModel.UserThemeCustomization.Appearance = colorScheme == .dark ? .dark : .light
        let resolved = model.userThemeCustomization.resolvedColors(for: appearance)
        let isCustomThemeEnabled = model.userThemeCustomization.isEnabled
        return themedBackground(
            baseHex: isCustomThemeEnabled
                ? (resolved.backgroundHex ?? tokens.palette.backgroundHex)
                : tokens.palette.backgroundHex,
            gradientHex: isCustomThemeEnabled ? resolved.chatGradientHex : nil
        )
    }

    private var runtimeConfigCard: some View {
        Group {
            if isRuntimeConfigExpanded {
                codexConfigCard
            } else {
                SettingsSectionCard(
                    title: "Codex Config",
                    subtitle: "Advanced config editor. Expand only when needed to keep Runtime settings responsive."
                ) {
                    Button("Open Config Editor") {
                        isRuntimeConfigExpanded = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var accountCard: some View {
        SettingsSectionCard(
            title: "Account",
            subtitle: "Account authentication and keychain-backed key management."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsFieldRow(label: "Current") {
                    Text(model.accountSummaryText)
                        .foregroundStyle(.secondary)
                }

                SettingsFieldRow(label: "Auth mode") {
                    Text(model.accountState.authMode.rawValue)
                        .foregroundStyle(.secondary)
                }

                SettingsFieldRow(label: "Name") {
                    TextField("Shown in sidebar", text: $preferredAccountDisplayName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .accessibilityLabel("Display name")
                }

                Text("Your name appears in the bottom-left account label. Leave empty to use your account email or auth title.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.isSignedInWithChatGPT {
                    Label("Signed in with ChatGPT.", systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous)
                                .fill(.green.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous)
                                .strokeBorder(.green.opacity(0.24))
                        )
                        .accessibilityLabel("Signed in with ChatGPT")
                }

                if let message = model.accountStatusMessage {
                    accountStatusBanner(message)
                }

                HStack(spacing: 10) {
                    Button {
                        model.signInWithChatGPT()
                    } label: {
                        Label("Sign in with ChatGPT", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(model.isAccountOperationInProgress)

                    Button {
                        model.presentAPIKeyPrompt()
                    } label: {
                        Label("Use API Key…", systemImage: "key")
                    }
                    .disabled(model.isAccountOperationInProgress)

                    Button {
                        model.launchDeviceCodeLogin()
                    } label: {
                        Label("Device-Code Login", systemImage: "qrcode")
                    }
                    .disabled(model.isAccountOperationInProgress)

                    Button(role: .destructive) {
                        model.logoutAccount()
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(model.isAccountOperationInProgress)
                }
                .buttonStyle(.bordered)

                Text("API keys are stored in macOS Keychain. Per-project secret references are tracked in local metadata.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceCard: some View {
        let activePresetID = model.activeThemePresetID

        return SettingsSectionCard(
            title: "Theme Studio",
            subtitle: "Customize accent, sidebar, and chat surfaces. Changes apply instantly."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Presets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(minimum: 90), spacing: 8),
                        count: Self.themePresetGridColumnCount
                    ),
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(model.themePresets) { preset in
                        themePresetChip(
                            title: preset.title,
                            isSelected: activePresetID == preset.id
                        ) {
                            model.applyThemePreset(preset)
                            isThemeCustomEditorExpanded = false
                        }
                    }

                    themePresetChip(
                        title: "Custom",
                        symbolName: "slider.horizontal.3",
                        isSelected: isThemeCustomEditorExpanded && !model.isSavedCustomThemeActive
                    ) {
                        let isOpeningEditor = !isThemeCustomEditorExpanded
                        isThemeCustomEditorExpanded = isOpeningEditor
                        if isOpeningEditor {
                            customThemeEditorAppearance = colorScheme == .dark ? .dark : .light
                        }
                    }

                    if let savedCustomThemePreset = model.savedCustomThemePreset {
                        themePresetChip(
                            title: savedCustomThemePreset.displayName,
                            symbolName: "bookmark.fill",
                            isSelected: model.isSavedCustomThemeActive
                        ) {
                            model.applySavedCustomThemePreset()
                            isThemeCustomEditorExpanded = false
                        }
                    }
                }
                .accessibilityLabel("Theme presets")

                if isThemeCustomEditorExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable custom theme", isOn: userThemeEnabledBinding)

                        Text("By default, light mode stays bright and dark mode stays deep black. Enable overrides only where you want changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Theme variant", selection: $customThemeEditorAppearance) {
                            Text("Dark").tag(AppModel.UserThemeCustomization.Appearance.dark)
                            Text("Light").tag(AppModel.UserThemeCustomization.Appearance.light)
                        }
                        .pickerStyle(.segmented)

                        Text(
                            customThemeEditorAppearance == .dark
                                ? "Dark values apply when the app is in Dark appearance."
                                : "Light values apply when the app is in Light appearance. Unset fields inherit from Dark."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        SettingsFieldRow(label: "Custom preset") {
                            HStack(spacing: 8) {
                                TextField("My Theme", text: $customThemeNameDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 220)
                                    .accessibilityLabel("Custom theme name")

                                Button(model.savedCustomThemePreset == nil ? "Save" : "Update") {
                                    model.saveCurrentThemeAsCustomPreset(named: customThemeNameDraft)
                                    syncThemeDraftFromModel()
                                }
                                .buttonStyle(.borderedProminent)

                                if model.savedCustomThemePreset != nil {
                                    Button("Clear") {
                                        model.clearSavedCustomThemePreset()
                                        syncThemeDraftFromModel()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        themeColorPickerRow(
                            "Primary accent",
                            darkKeyPath: \.accentHex,
                            lightKeyPath: \.lightAccentHex,
                            resolvedKeyPath: \.accentHex,
                            darkFallback: DesignTokens.systemDark.palette.accentHex,
                            lightFallback: DesignTokens.systemLight.palette.accentHex
                        )
                        themeColorPickerRow(
                            "Sidebar",
                            darkKeyPath: \.sidebarHex,
                            lightKeyPath: \.lightSidebarHex,
                            resolvedKeyPath: \.sidebarHex,
                            darkFallback: DesignTokens.systemDark.palette.sidebarHex,
                            lightFallback: DesignTokens.systemLight.palette.sidebarHex
                        )
                        themeColorPickerRow(
                            "Main chat panel",
                            darkKeyPath: \.backgroundHex,
                            lightKeyPath: \.lightBackgroundHex,
                            resolvedKeyPath: \.backgroundHex,
                            darkFallback: DesignTokens.systemDark.palette.backgroundHex,
                            lightFallback: DesignTokens.systemLight.palette.backgroundHex
                        )
                        themeColorPickerRow(
                            "Card / input panel",
                            darkKeyPath: \.panelHex,
                            lightKeyPath: \.lightPanelHex,
                            resolvedKeyPath: \.panelHex,
                            darkFallback: DesignTokens.systemDark.palette.panelHex,
                            lightFallback: DesignTokens.systemLight.palette.panelHex
                        )

                        Divider()

                        themeColorPickerRow(
                            "Sidebar gradient",
                            darkKeyPath: \.sidebarGradientHex,
                            lightKeyPath: \.lightSidebarGradientHex,
                            resolvedKeyPath: \.sidebarGradientHex,
                            darkFallback: DesignTokens.systemDark.palette.sidebarHex,
                            lightFallback: DesignTokens.systemLight.palette.sidebarHex
                        )
                        themeColorPickerRow(
                            "Chat gradient",
                            darkKeyPath: \.chatGradientHex,
                            lightKeyPath: \.lightChatGradientHex,
                            resolvedKeyPath: \.chatGradientHex,
                            darkFallback: DesignTokens.systemDark.palette.backgroundHex,
                            lightFallback: DesignTokens.systemLight.palette.backgroundHex
                        )

                        Picker(
                            "Surface mode",
                            selection: Binding(
                                get: { model.userThemeCustomization.transparencyMode },
                                set: { mode in
                                    updateUserThemeCustomization { customization in
                                        customization.transparencyMode = mode
                                    }
                                }
                            )
                        ) {
                            Text("Solid").tag(AppModel.UserThemeCustomization.TransparencyMode.solid)
                            Text("Glass (Experimental)").tag(AppModel.UserThemeCustomization.TransparencyMode.glass)
                        }
                        .pickerStyle(.segmented)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Gradient intensity")
                                    .font(.subheadline)
                                Spacer(minLength: 0)
                                Text("\(Int((model.userThemeCustomization.gradientStrength * 100).rounded()))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Slider(value: userThemeGradientStrengthBinding, in: 0 ... 1)
                                .accessibilityLabel("Gradient intensity")
                        }

                        if model.userThemeCustomization.transparencyMode == .glass {
                            Text("Glass mode applies transparent backgrounds to major app surfaces for a desktop-through effect.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }

                HStack(spacing: 8) {
                    Button("Edit Custom Theme") {
                        isThemeCustomEditorExpanded = true
                        customThemeEditorAppearance = colorScheme == .dark ? .dark : .light
                    }
                    .buttonStyle(.bordered)

                    Button("Reset to Default") {
                        model.resetUserThemeCustomization()
                        isThemeCustomEditorExpanded = false
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.userThemeCustomization == .default)
                }

                ThemeStudioPreview(customization: model.userThemeCustomization, tokens: tokens)
            }
        }
    }

    private var runtimeDefaultsCard: some View {
        SettingsSectionCard(
            title: "Runtime Defaults",
            subtitle: "Defaults used when creating turns and projects."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("Runtime default (auto)", text: $runtimeModelDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Default model ID")

                    Menu("Preset") {
                        if model.runtimeDefaultModelID != nil {
                            Button("Runtime default") {
                                runtimeModelDraft = ""
                                model.setDefaultModel("")
                            }

                            if !model.modelPresets.isEmpty {
                                Divider()
                            }
                        }

                        ForEach(model.modelPresets, id: \.self) { preset in
                            Button(model.modelMenuLabel(for: preset)) {
                                runtimeModelDraft = preset
                                model.setDefaultModel(preset)
                            }
                        }
                    }

                    Button("Apply") {
                        model.setDefaultModel(runtimeModelDraft)
                    }
                    .buttonStyle(.bordered)
                }

                Text(
                    model.isUsingRuntimeDefaultModel
                        ? "Using runtime default model (\(model.defaultModelDisplayName))."
                        : "Pinned model: \(model.defaultModelDisplayName)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if model.canChooseReasoningForSelectedModel {
                    if model.reasoningPresets.count <= 3 {
                        Picker(
                            "Reasoning",
                            selection: Binding(
                                get: { model.defaultReasoning },
                                set: { model.setDefaultReasoning($0) }
                            )
                        ) {
                            ForEach(model.reasoningPresets, id: \.self) { level in
                                Text(level.title).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Picker(
                            "Reasoning",
                            selection: Binding(
                                get: { model.defaultReasoning },
                                set: { model.setDefaultReasoning($0) }
                            )
                        ) {
                            ForEach(model.reasoningPresets, id: \.self) { level in
                                Text(level.title).tag(level)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                if model.canChooseWebSearchForSelectedModel {
                    Picker(
                        "Web search",
                        selection: Binding(
                            get: { model.defaultWebSearch },
                            set: { model.setDefaultWebSearch($0) }
                        )
                    ) {
                        ForEach(model.webSearchPresets, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Picker(
                        "Conversation stream",
                        selection: Binding(
                            get: { model.transcriptDetailLevel },
                            set: { model.setTranscriptDetailLevel($0) }
                        )
                    ) {
                        ForEach(TranscriptDetailLevel.allCases, id: \.self) { level in
                            Text(model.transcriptDetailLevelTitle(level)).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(model.transcriptDetailLevelDescription(model.transcriptDetailLevel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Composer controls inherit these defaults. Project safety policy still clamps effective web-search behavior at turn time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var codexConfigCard: some View {
        CodexConfigSettingsSection(model: model)
    }

    @ViewBuilder
    private var generalProjectContent: some View {
        if let project = model.generalProject {
            generalProjectSummaryCard(project)
            generalProjectSafetyCard
            generalProjectMemoryCard
        } else {
            SettingsSectionCard(
                title: "General Project",
                subtitle: "Shared baseline project for defaults and global memory behavior."
            ) {
                Text("General project is unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func generalProjectSummaryCard(_ generalProject: ProjectRecord) -> some View {
        SettingsSectionCard(
            title: "General Project",
            subtitle: "Baseline project metadata and trust state."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsFieldRow(label: "Name") {
                    Text(generalProject.name)
                        .foregroundStyle(.secondary)
                }

                SettingsFieldRow(label: "Path") {
                    Text(generalProject.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                SettingsFieldRow(label: "Trust") {
                    SettingsStatusBadge(
                        generalProject.trustState == .trusted ? "Trusted" : "Untrusted",
                        tone: generalProject.trustState == .trusted ? .accent : .neutral
                    )
                }

                HStack(spacing: 8) {
                    Button("Trust") {
                        model.trustGeneralProject()
                    }
                    .buttonStyle(.bordered)
                    .disabled(generalProject.trustState == .trusted)
                    .accessibilityHint("Marks this project as trusted.")

                    Button("Mark Untrusted", role: .destructive) {
                        model.untrustGeneralProject()
                    }
                    .buttonStyle(.bordered)
                    .disabled(generalProject.trustState == .untrusted)
                    .accessibilityHint("Marks this project as untrusted.")
                }
            }
        }
    }

    private var generalProjectSafetyCard: some View {
        SettingsSectionCard(
            title: "Trust & Safety",
            subtitle: "Controls for sandboxing, approvals, network access, and web search."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Sandbox mode", selection: $generalSandboxMode) {
                    ForEach(ProjectSandboxMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Picker("Approval policy", selection: $generalApprovalPolicy) {
                    ForEach(ProjectApprovalPolicy.allCases, id: \.self) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Allow network access in workspace-write", isOn: $generalNetworkAccess)
                    .disabled(generalSandboxMode != .workspaceWrite)
                    .onChange(of: generalSandboxMode) { _, newValue in
                        generalNetworkAccess = ProjectSettingsSheet.clampedNetworkAccess(
                            for: newValue,
                            networkAccess: generalNetworkAccess
                        )
                    }
                    .accessibilityHint("Only available when sandbox mode is workspace-write.")

                Picker("Web search mode", selection: $generalWebSearchMode) {
                    ForEach(ProjectWebSearchMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Button("Save General Safety Settings") {
                    let settings = ProjectSafetySettings(
                        sandboxMode: generalSandboxMode,
                        approvalPolicy: generalApprovalPolicy,
                        networkAccess: generalNetworkAccess,
                        webSearch: generalWebSearchMode
                    )

                    if model.requiresDangerConfirmation(
                        sandboxMode: settings.sandboxMode,
                        approvalPolicy: settings.approvalPolicy
                    ) {
                        pendingGeneralSafetySettings = settings
                        generalDangerConfirmationInput = ""
                        generalDangerConfirmationError = nil
                        isGeneralDangerConfirmationVisible = true
                    } else {
                        model.updateGeneralProjectSafetySettings(
                            sandboxMode: settings.sandboxMode,
                            approvalPolicy: settings.approvalPolicy,
                            networkAccess: settings.networkAccess,
                            webSearch: settings.webSearch
                        )
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Saves updated safety controls for the General project.")

                if let status = model.projectStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var generalProjectMemoryCard: some View {
        SettingsSectionCard(
            title: "Memory",
            subtitle: "Memory write and retrieval behavior for the General project."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("After each completed turn", selection: $generalMemoryWriteMode) {
                    Text("Off").tag(ProjectMemoryWriteMode.off)
                    Text("Summaries only").tag(ProjectMemoryWriteMode.summariesOnly)
                    Text("Summaries + key facts").tag(ProjectMemoryWriteMode.summariesAndKeyFacts)
                }
                .pickerStyle(.menu)
                .disabled(isSyncingGeneralProject)

                Toggle("Enable semantic retrieval (advanced)", isOn: $generalMemoryEmbeddingsEnabled)
                    .disabled(isSyncingGeneralProject)

                Button("Save General Memory Settings") {
                    model.updateGeneralProjectMemorySettings(
                        writeMode: generalMemoryWriteMode,
                        embeddingsEnabled: generalMemoryEmbeddingsEnabled
                    )
                }
                .buttonStyle(.bordered)

                Text("General project memory is stored under the General project folder in `memory/*.md`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let memoryStatus = model.memoryStatusMessage {
                    Text(memoryStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var safetyDefaultsCard: some View {
        SettingsSectionCard(
            title: "Safety Defaults",
            subtitle: "Defaults for newly created projects."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Sandbox mode", selection: $safetySandboxMode) {
                    ForEach(ProjectSandboxMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Picker("Approval policy", selection: $safetyApprovalPolicy) {
                    ForEach(ProjectApprovalPolicy.allCases, id: \.self) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Allow network access in workspace-write", isOn: $safetyNetworkAccess)
                    .disabled(safetySandboxMode != .workspaceWrite)
                    .onChange(of: safetySandboxMode) { _, newValue in
                        safetyNetworkAccess = ProjectSettingsSheet.clampedNetworkAccess(
                            for: newValue,
                            networkAccess: safetyNetworkAccess
                        )
                    }
                    .accessibilityHint("Only available when sandbox mode is workspace-write.")

                Picker("Web search mode", selection: $safetyWebSearchMode) {
                    ForEach(ProjectWebSearchMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Button("Save Global Safety Defaults…") {
                    pendingSafetyDefaults = ProjectSafetySettings(
                        sandboxMode: safetySandboxMode,
                        approvalPolicy: safetyApprovalPolicy,
                        networkAccess: safetyNetworkAccess,
                        webSearch: safetyWebSearchMode
                    )
                    isSafetyApplyPromptVisible = true
                }
                .buttonStyle(.bordered)

                Text("These defaults initialize new projects. After saving, you can choose whether to bulk-apply them to existing projects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let runtimeDefaultsStatusMessage = model.runtimeDefaultsStatusMessage {
                    Text(runtimeDefaultsStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var experimentalCard: some View {
        SettingsSectionCard(
            title: "Experimental",
            subtitle: "Experimental values are managed through config.toml."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Use the Runtime section's Codex Config editor to change experimental flags.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 8) {
                    SettingsStatusBadge(
                        model.areAdvancedExecutableModsUnlocked ? "Advanced executable mods: Unlocked" : "Advanced executable mods: Locked",
                        tone: model.areAdvancedExecutableModsUnlocked ? .accent : .neutral
                    )
                    Spacer(minLength: 0)
                }

                if model.areAdvancedExecutableModsUnlocked {
                    Button("Lock advanced executable mods") {
                        model.setAdvancedExecutableModsUnlocked(false)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Unlock advanced executable mods…") {
                        advancedModsUnlockInput = ""
                        advancedModsUnlockError = nil
                        isAdvancedModsUnlockConfirmationVisible = true
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("Non-vetted mods with hooks or automations are blocked by default for new installs. Vetted first-party packs remain available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var diagnosticsCard: some View {
        SettingsSectionCard(
            title: "Diagnostics",
            subtitle: "Capture a support-ready diagnostics bundle with non-sensitive logs."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    model.copyDiagnosticsBundle()
                } label: {
                    Label("Copy diagnostics bundle", systemImage: "doc.zipper")
                }
                .buttonStyle(.bordered)
                .disabled(model.isAccountOperationInProgress)

                Button {
                    model.copyExtensibilityDiagnostics()
                } label: {
                    Label("Copy extensibility diagnostics", systemImage: "doc.badge.gearshape")
                }
                .buttonStyle(.bordered)
                .disabled(model.isAccountOperationInProgress)

                Stepper(
                    value: Binding(
                        get: { model.extensibilityDiagnosticsRetentionLimit },
                        set: { model.setExtensibilityDiagnosticsRetentionLimit($0) }
                    ),
                    in: 25 ... 500,
                    step: 25
                ) {
                    Text("Retain up to \(model.extensibilityDiagnosticsRetentionLimit) extensibility events")
                }

                Text("Exports non-sensitive runtime state and logs as a zip archive, then copies the saved file path to clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Extensibility diagnostics export includes normalized skill/mod/extension/launchd failure events for support and audit workflows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var storageCard: some View {
        SettingsSectionCard(
            title: "Storage",
            subtitle: "Storage root and managed metadata location."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsFieldRow(label: "Root") {
                    Text(model.storageRootPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    Button {
                        model.changeStorageRoot()
                    } label: {
                        Label("Change Root…", systemImage: "folder.badge.gearshape")
                    }

                    Button {
                        model.revealStorageRoot()
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Button {
                        model.repairCodexHome()
                    } label: {
                        Label("Repair Codex Home", systemImage: "wrench.and.screwdriver")
                    }
                    .disabled(model.isTurnInProgress || model.isStorageRepairInProgress)
                }
                .buttonStyle(.bordered)

                if model.lastCodexHomeQuarantinePath != nil {
                    Button {
                        model.revealLastCodexHomeQuarantine()
                    } label: {
                        Label("Reveal Last Quarantine", systemImage: "archivebox")
                    }
                    .buttonStyle(.bordered)
                }

                Text("Changing the storage root moves CodexChat-managed data and requires an app restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Codex Home repair quarantines stale runtime session/index cache and keeps config, auth, history, skills, and instructions intact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let storageStatusMessage = model.storageStatusMessage {
                    Text(storageStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var userThemeEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.userThemeCustomization.isEnabled },
            set: { isEnabled in
                updateUserThemeCustomization { customization in
                    customization.isEnabled = isEnabled
                }
            }
        )
    }

    private func themePresetChip(
        title: String,
        symbolName: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.caption.weight(.semibold))
                }

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.12 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.26 : 0.14))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var userThemeGradientStrengthBinding: Binding<Double> {
        Binding(
            get: { model.userThemeCustomization.gradientStrength },
            set: { value in
                updateUserThemeCustomization { customization in
                    customization.gradientStrength = AppModel.UserThemeCustomization.clampedGradientStrength(value)
                }
            }
        )
    }

    private func themeColorPickerRow(
        _ label: String,
        darkKeyPath: WritableKeyPath<AppModel.UserThemeCustomization, String?>,
        lightKeyPath: WritableKeyPath<AppModel.UserThemeCustomization, String?>,
        resolvedKeyPath: KeyPath<AppModel.UserThemeCustomization.ResolvedColors, String?>,
        darkFallback: String,
        lightFallback: String
    ) -> some View {
        let activeKeyPath = customThemeEditorAppearance == .dark ? darkKeyPath : lightKeyPath
        let fallbackHex = customThemeEditorAppearance == .dark ? darkFallback : lightFallback
        let resetLabel = customThemeEditorAppearance == .dark ? "System" : "Use Dark"
        let currentValue = model.userThemeCustomization[keyPath: activeKeyPath]

        return SettingsFieldRow(label: label) {
            HStack(spacing: 8) {
                ColorPicker(
                    label,
                    selection: Binding(
                        get: { Color(hex: themeColorForDisplay(resolvedKeyPath, fallback: fallbackHex)) },
                        set: { color in
                            guard let hex = color.codexHexString() else { return }
                            updateUserThemeCustomization { customization in
                                customization[keyPath: activeKeyPath] = hex
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()

                Text(currentValue ?? resetLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 84, alignment: .trailing)

                Button(resetLabel) {
                    updateUserThemeCustomization { customization in
                        customization[keyPath: activeKeyPath] = nil
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(currentValue == nil)
            }
        }
    }

    private func themeColorForDisplay(
        _ keyPath: KeyPath<AppModel.UserThemeCustomization.ResolvedColors, String?>,
        fallback: String
    ) -> String {
        model.userThemeCustomization.resolvedColors(for: customThemeEditorAppearance)[keyPath: keyPath] ?? fallback
    }

    @ViewBuilder
    private func themedBackground(baseHex: String, gradientHex: String?) -> some View {
        if model.userThemeCustomization.isEnabled {
            ZStack {
                Color(hex: baseHex)
                    .opacity(model.isTransparentThemeMode ? 0.58 : 1)
                if let gradientHex, model.userThemeCustomization.gradientStrength > 0 {
                    LinearGradient(
                        colors: [Color(hex: baseHex), Color(hex: gradientHex)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(model.userThemeCustomization.gradientStrength)
                }
            }
        } else {
            Color(hex: baseHex)
        }
    }

    private func updateUserThemeCustomization(_ mutate: (inout AppModel.UserThemeCustomization) -> Void) {
        var next = model.userThemeCustomization
        mutate(&next)
        guard next != model.userThemeCustomization else { return }
        // Avoid publishing object changes during an in-flight view update cycle.
        DispatchQueue.main.async {
            model.setUserThemeCustomization(next)
        }
    }

    private enum AccountStatusTone {
        case info
        case success
        case error

        var symbolName: String {
            switch self {
            case .info:
                "info.circle.fill"
            case .success:
                "checkmark.circle.fill"
            case .error:
                "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info:
                .blue
            case .success:
                .green
            case .error:
                .red
            }
        }
    }

    private func accountStatusBanner(_ message: String) -> some View {
        let tone = accountStatusTone(for: message)

        return Label(message, systemImage: tone.symbolName)
            .font(.callout)
            .foregroundStyle(tone.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous)
                    .fill(tone.tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.radius.small, style: .continuous)
                    .strokeBorder(tone.tint.opacity(0.24))
            )
            .accessibilityLabel("Account status: \(message)")
    }

    private func accountStatusTone(for message: String) -> AccountStatusTone {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.contains("failed")
            || normalized.contains("unable")
            || normalized.contains("did not confirm")
            || normalized.contains("empty")
        {
            return .error
        }

        if normalized.contains("signed in")
            || normalized.contains("completed")
            || normalized.contains("restored")
        {
            return .success
        }

        return .info
    }

    private func syncSafetyDefaultsFromModel() {
        safetySandboxMode = model.defaultSafetySettings.sandboxMode
        safetyApprovalPolicy = model.defaultSafetySettings.approvalPolicy
        safetyNetworkAccess = model.defaultSafetySettings.networkAccess
        safetyWebSearchMode = model.defaultSafetySettings.webSearch
    }

    private func syncThemeDraftFromModel() {
        if let savedCustomThemePreset = model.savedCustomThemePreset {
            customThemeNameDraft = savedCustomThemePreset.displayName
        } else if customThemeNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customThemeNameDraft = "My Theme"
        }
    }

    private func syncGeneralProjectFromModel(force: Bool = false) {
        guard let project = model.generalProject else {
            lastSyncedGeneralProject = nil
            return
        }
        guard force || lastSyncedGeneralProject != project else {
            return
        }
        isSyncingGeneralProject = true
        generalSandboxMode = project.sandboxMode
        generalApprovalPolicy = project.approvalPolicy
        generalNetworkAccess = project.networkAccess
        generalWebSearchMode = project.webSearch
        generalMemoryWriteMode = project.memoryWriteMode
        generalMemoryEmbeddingsEnabled = project.memoryEmbeddingsEnabled
        lastSyncedGeneralProject = project
        isSyncingGeneralProject = false
    }
}

private struct ThemeStudioPreview: View {
    let customization: AppModel.UserThemeCustomization
    let tokens: DesignTokens
    @Environment(\.colorScheme) private var colorScheme

    private var resolved: AppModel.UserThemeCustomization.ResolvedColors {
        let appearance: AppModel.UserThemeCustomization.Appearance = colorScheme == .dark ? .dark : .light
        return customization.resolvedColors(for: appearance)
    }

    private var accentHex: String {
        customization.isEnabled ? (resolved.accentHex ?? tokens.palette.accentHex) : tokens.palette.accentHex
    }

    private var sidebarHex: String {
        customization.isEnabled ? (resolved.sidebarHex ?? tokens.palette.sidebarHex) : tokens.palette.sidebarHex
    }

    private var chatHex: String {
        customization.isEnabled ? (resolved.backgroundHex ?? tokens.palette.backgroundHex) : tokens.palette.backgroundHex
    }

    private var panelHex: String {
        customization.isEnabled ? (resolved.panelHex ?? tokens.palette.panelHex) : tokens.palette.panelHex
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color(hex: sidebarHex)
                    .opacity(customization.isGlassEnabled ? 0.58 : 1)
                if customization.isEnabled {
                    let gradientHex = resolved.sidebarGradientHex ?? sidebarHex
                    LinearGradient(
                        colors: [Color(hex: sidebarHex), Color(hex: gradientHex)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(customization.gradientStrength)
                }

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 8)
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: accentHex).opacity(0.9))
                        .frame(height: 10)
                }
                .padding(8)
            }
            .frame(width: 76)

            ZStack {
                Color(hex: chatHex)
                    .opacity(customization.isGlassEnabled ? 0.58 : 1)
                if customization.isEnabled {
                    let gradientHex = resolved.chatGradientHex ?? chatHex
                    LinearGradient(
                        colors: [Color(hex: chatHex), Color(hex: gradientHex)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(customization.gradientStrength)
                }

                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(hex: panelHex).opacity(0.95))
                        .frame(height: 20)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(hex: accentHex).opacity(0.22))
                        .frame(height: 16)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(hex: panelHex).opacity(0.8))
                        .frame(height: 14)
                }
                .padding(10)
            }
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
        .accessibilityHidden(true)
    }
}

private extension Color {
    func codexHexString() -> String? {
        guard let converted = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int(round(converted.redComponent * 255))
        let green = Int(round(converted.greenComponent * 255))
        let blue = Int(round(converted.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
