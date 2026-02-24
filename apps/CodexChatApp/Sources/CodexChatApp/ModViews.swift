import CodexChatCore
import CodexChatUI
import CodexMods
import SwiftUI

@MainActor
struct ModsCanvas: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @State private var isInstallModSheetVisible = false
    private let sharingGuideURL = URL(string: "https://github.com/bikz/codexchat/blob/main/docs-public/MODS_SHARING.md")
    private let modCardColumns = [
        GridItem(.flexible(minimum: 220), spacing: 10, alignment: .top),
        GridItem(.flexible(minimum: 220), spacing: 10, alignment: .top),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            modsSurface
        }
        .background(SkillsModsTheme.canvasBackground(tokens: tokens))
        .navigationTitle("")
        .onAppear {
            model.refreshModsSurface()
        }
        .sheet(isPresented: $isInstallModSheetVisible) {
            InstallModSheet(model: model, isPresented: $isInstallModSheetVisible)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Mods")
                .font(.title3.weight(.semibold))

            Text(SkillsModsPresentation.extensionExperimentalBadge)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.orange.opacity(0.24)))

            Button {
                model.refreshModsSurface()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button {
                model.revealGlobalModsFolder()
            } label: {
                Label("Global Folder", systemImage: "folder.badge.gearshape")
            }
            .buttonStyle(.bordered)

            Button {
                model.revealProjectModsFolder()
            } label: {
                Label("Project Folder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedProject == nil)

            Button {
                isInstallModSheetVisible = true
            } label: {
                Label("Install Mod", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SkillsModsTheme.pageHorizontalInset)
        .padding(.top, tokens.spacing.small)
        .padding(.bottom, tokens.spacing.xSmall)
    }

    @ViewBuilder
    private var modsSurface: some View {
        switch model.modsState {
        case .idle:
            EmptyStateView(
                title: "Mods ready",
                message: "Enable a global or per-project mod to customize the UI.",
                systemImage: "paintbrush"
            )
            .padding(SkillsModsTheme.pageHorizontalInset)
        case .loading:
            LoadingStateView(title: "Loading mods…")
                .padding(SkillsModsTheme.pageHorizontalInset)
        case let .failed(message):
            ErrorStateView(title: "Mods unavailable", message: message, actionLabel: "Retry") {
                model.refreshModsSurface()
            }
            .padding(SkillsModsTheme.pageHorizontalInset)
        case let .loaded(surface):
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Precedence: defaults < global mod < project mod.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    whatYouCanBuildSection
                    modGuideSection
                    globalSection(surface: surface)
                    projectSection(surface: surface)

                    if let status = model.modStatusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, SkillsModsTheme.pageHorizontalInset)
                .padding(.vertical, 16)
            }
        }
    }

    private func globalSection(surface: AppModel.ModsSurfaceModel) -> some View {
        SkillsModsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Global Mods")
                        .font(.title3.weight(.semibold))

                    Spacer()

                    Button("Clear") {
                        model.setGlobalMod(nil)
                    }
                    .buttonStyle(.bordered)
                    .disabled(surface.selectedGlobalModPath == nil)

                    Button("Create Sample") {
                        model.createSampleGlobalMod()
                    }
                    .buttonStyle(.bordered)
                }

                if surface.globalMods.isEmpty {
                    compactEmpty(
                        title: "No global mods found",
                        message: "Add a mod directory containing `codex.mod.json` + `ui.mod.json` under the global mods folder.",
                        systemImage: "folder"
                    )
                } else {
                    Text("Checked = active for this scope. Installed mods remain available from the Mods bar quick switch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: modCardColumns, alignment: .leading, spacing: 10) {
                        ForEach(surface.globalMods) { mod in
                            modOptionCard(
                                mod: mod,
                                scope: .global,
                                isEnabled: surface.enabledGlobalModIDs.contains(mod.definition.manifest.id),
                                isSelected: surface.selectedGlobalModPath == mod.directoryPath,
                                onSelect: { model.setGlobalMod(mod) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var modGuideSection: some View {
        SkillsModsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Builder Guide", systemImage: "sparkles.rectangle.stack")
                        .font(.title3.weight(.semibold))

                    Spacer()

                    Text("Canonical")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SkillsModsTheme.headerBackground(tokens: tokens), in: Capsule())
                }

                if let sharingGuideURL {
                    Link(destination: sharingGuideURL) {
                        Label("Open guide on GitHub", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.medium))
                    }
                }

                guideStep(
                    number: 1,
                    text: "Click `Create Sample` in Global Mod or Project Mod to generate a starter mod folder."
                )
                guideStep(
                    number: 2,
                    text: "Edit `ui.mod.json`: keep `schemaVersion: 1`, configure hooks/automations, and use `uiSlots.modsBar` for Mods bar output."
                )
                guideStep(
                    number: 3,
                    text: "For sharing, commit that mod directory to any git repository and share the repo URL."
                )
                guideStep(
                    number: 4,
                    text: "Install from local path or GitHub URL in `Install Mod` and review permissions before enabling."
                )
            }
        }
    }

    private var whatYouCanBuildSection: some View {
        SkillsModsCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("What You Can Build", systemImage: "hammer.fill")
                    .font(.title3.weight(.semibold))

                ForEach(Array(SkillsModsPresentation.modArchetypes.enumerated()), id: \.offset) { index, archetype in
                    guideStep(number: index + 1, text: "\(archetype.title): \(archetype.detail)")
                }
            }
        }
    }

    private func projectSection(surface: AppModel.ModsSurfaceModel) -> some View {
        SkillsModsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Project Mods")
                        .font(.title3.weight(.semibold))

                    Spacer()

                    Button("Clear") {
                        model.setProjectMod(nil)
                    }
                    .buttonStyle(.bordered)
                    .disabled(surface.selectedProjectModPath == nil)

                    Button("Create Sample") {
                        model.createSampleProjectMod()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.selectedProject == nil)
                }

                if model.selectedProject == nil {
                    compactEmpty(
                        title: "Select a project",
                        message: "Project mods are stored in the selected project folder under `mods/`.",
                        systemImage: "folder"
                    )
                } else if surface.projectMods.isEmpty {
                    compactEmpty(
                        title: "No project mods found",
                        message: "Add a mod directory containing `codex.mod.json` + `ui.mod.json` under `mods/` in the selected project.",
                        systemImage: "doc.badge.plus"
                    )
                } else {
                    Text("Checked = active for this scope. Installed mods remain available from the Mods bar quick switch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: modCardColumns, alignment: .leading, spacing: 10) {
                        ForEach(surface.projectMods) { mod in
                            modOptionCard(
                                mod: mod,
                                scope: .project,
                                isEnabled: surface.enabledProjectModIDs.contains(mod.definition.manifest.id),
                                isSelected: surface.selectedProjectModPath == mod.directoryPath,
                                onSelect: { model.setProjectMod(mod) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func modOptionCard(
        mod: DiscoveredUIMod,
        scope: ExtensionInstallScope,
        isEnabled: Bool,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if mod.definition.uiSlots?.modsBar?.enabled == true {
                    Image(systemName: modsBarSymbolName(for: mod, scope: scope))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(mod.definition.manifest.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(hex: tokens.palette.accentHex))
                }

                Menu {
                    Button("Set Active") {
                        onSelect()
                    }

                    if isSelected {
                        Button("Clear Active Selection") {
                            clearModSelection(scope: scope)
                        }
                    }

                    Divider()

                    Button(isEnabled ? "Disable Runtime" : "Enable Runtime") {
                        model.setInstalledModEnabled(mod, scope: scope, enabled: !isEnabled)
                    }
                    .disabled(model.isModOperationInProgress)

                    if mod.definition.uiSlots?.modsBar?.enabled == true {
                        Menu("Set Icon") {
                            Button("Automatic") {
                                model.setModsBarIconOverride(modID: mod.definition.manifest.id, symbolName: nil)
                            }

                            Divider()

                            ForEach(model.modsBarIconPresetSymbols(), id: \.self) { symbol in
                                Button {
                                    model.setModsBarIconOverride(modID: mod.definition.manifest.id, symbolName: symbol)
                                } label: {
                                    Label(symbol, systemImage: symbol)
                                }
                            }
                        }
                    }

                    Button("Update/Reinstall") {
                        model.updateInstalledMod(mod, scope: scope)
                    }
                    .disabled(model.isModOperationInProgress)

                    Button("Uninstall", role: .destructive) {
                        model.uninstallInstalledMod(mod, scope: scope)
                    }
                    .disabled(model.isModOperationInProgress)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
            }

            Text("v\(mod.definition.manifest.version)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if let author = mod.definition.manifest.author, !author.isEmpty {
                Text(author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                ForEach(SkillsModsPresentation.modCapabilities(mod), id: \.rawValue) { capability in
                    modCapabilityBadge(capability)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                modStatusPill(SkillsModsPresentation.modStatus(mod).rawValue)
                modRuntimePill(isEnabled: isEnabled)
                Spacer(minLength: 0)
            }

            if let summary = model.extensionAutomationHealthByModID[mod.definition.manifest.id] {
                automationHealthRow(summary)
            }

            Text(SkillsModsPresentation.modDirectoryName(mod))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelected
                        ? Color(hex: tokens.palette.accentHex).opacity(0.14)
                        : SkillsModsTheme.cardBackground(tokens: tokens)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color(hex: tokens.palette.accentHex).opacity(0.36)
                        : SkillsModsTheme.subtleBorder(tokens: tokens)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            onSelect()
        }
    }

    private func clearModSelection(scope: ExtensionInstallScope) {
        switch scope {
        case .global:
            model.setGlobalMod(nil)
        case .project:
            model.setProjectMod(nil)
        }
    }

    private func modsBarSymbolName(for mod: DiscoveredUIMod, scope: ExtensionInstallScope) -> String {
        let optionScope: AppModel.ModsBarQuickSwitchOption.Scope = switch scope {
        case .global:
            .global
        case .project:
            .project
        }
        let option = AppModel.ModsBarQuickSwitchOption(scope: optionScope, mod: mod, isSelected: false)
        return model.modsBarQuickSwitchSymbolName(for: option)
    }

    private func modCapabilityBadge(_ capability: SkillsModsPresentation.ModCapability) -> some View {
        let isPrivileged = capability == .privileged

        return Text(capability.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(isPrivileged ? .orange : .secondary)
            .background((isPrivileged ? Color.orange : Color.primary).opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder((isPrivileged ? Color.orange : Color.primary).opacity(0.16)))
    }

    private func modStatusPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(SkillsModsTheme.headerBackground(tokens: tokens), in: Capsule())
            .overlay(Capsule().strokeBorder(SkillsModsTheme.subtleBorder(tokens: tokens)))
    }

    private func modRuntimePill(isEnabled: Bool) -> some View {
        Text(isEnabled ? "Runtime On" : "Runtime Off")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isEnabled ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((isEnabled ? Color.green : Color.primary).opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder((isEnabled ? Color.green : Color.primary).opacity(0.16)))
    }

    private func automationHealthRow(_ summary: AppModel.ExtensionAutomationHealthSummary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: summary.hasFailures ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundStyle(summary.hasFailures ? .orange : .secondary)

            Text("Automations \(summary.automationCount)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(summary.hasFailures ? .orange : .secondary)

            if summary.hasFailures {
                Text("(\(summary.failingAutomationCount) failing)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if let nextRunAt = summary.nextRunAt {
                Text("next")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(nextRunAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let lastRunAt = summary.lastRunAt {
                Text("last")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(lastRunAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if summary.launchdScheduledAutomationCount > 0 || summary.hasLaunchdFailures {
                Text(
                    summary.hasLaunchdFailures
                        ? "bg issues \(summary.launchdFailingAutomationCount)"
                        : "bg active \(summary.launchdScheduledAutomationCount)"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(summary.hasLaunchdFailures ? .orange : .secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func compactEmpty(title: String, message: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(Color(hex: tokens.palette.accentHex))

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SkillsModsTheme.cardBackground(tokens: tokens))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SkillsModsTheme.subtleBorder(tokens: tokens))
        )
    }

    private func guideStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var catalogSection: some View {
        EmptyView()
    }
}

struct InstallModSheet: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool

    @State private var source = ""
    @State private var scope: ExtensionInstallScope = .project
    @State private var trustConfirmed = false
    @State private var reviewState: AppModel.SurfaceState<ModInstallPreview> = .idle

    private var isTrustedSource: Bool {
        model.isTrustedModSource(source)
    }

    private var hasReviewedPackage: Bool {
        guard case let .loaded(preview) = reviewState else { return false }
        return preview.source == source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canReview: Bool {
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (scope == .global || model.selectedProject != nil)
    }

    private var canSubmit: Bool {
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (isTrustedSource || trustConfirmed)
            && (scope == .global || model.selectedProject != nil)
            && hasReviewedPackage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Install Mod")
                .font(.title3.weight(.semibold))

            Text(SkillsModsPresentation.installModDescription)
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("https://github.com/org/mod-repo.git", text: $source)
                .textFieldStyle(.roundedBorder)

            Picker("Scope", selection: $scope) {
                Text("Project").tag(ExtensionInstallScope.project)
                Text("Global").tag(ExtensionInstallScope.global)
            }
            .pickerStyle(.segmented)

            if scope == .project, model.selectedProject == nil {
                Text("Select a project to install a project-scoped mod.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !isTrustedSource {
                Toggle("I trust this source and want to install it anyway.", isOn: $trustConfirmed)
                    .toggleStyle(.switch)

                Text("Unknown source detected. Installing may include unreviewed scripts or handlers.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            reviewSection

            if let status = model.modStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }

                Button("Review Package") {
                    reviewModSource()
                }
                .buttonStyle(.bordered)
                .disabled(!canReview || model.isModOperationInProgress)

                Button("Install") {
                    model.installMod(source: source, scope: scope)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || model.isModOperationInProgress)
            }
        }
        .padding(22)
        .frame(minWidth: 580)
        .onChange(of: source) { _, _ in
            trustConfirmed = false
            reviewState = .idle
        }
        .onChange(of: scope) { _, _ in
            reviewState = .idle
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        switch reviewState {
        case .idle:
            Text("Review package metadata and permissions before install.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loading:
            HStack(spacing: 8) {
                ActivityIndicatorGlyph(size: .small)
                Text("Reviewing package…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case let .failed(message):
            ErrorStateView(
                title: "Review failed",
                message: message,
                actionLabel: "Retry"
            ) {
                reviewModSource()
            }
        case let .loaded(preview):
            VStack(alignment: .leading, spacing: 8) {
                Text("Package review")
                    .font(.headline)

                Text("\(preview.packageManifest.name) v\(preview.packageManifest.version)")
                    .font(.subheadline.weight(.medium))

                Text(preview.packageManifest.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if let compatibility = preview.packageManifest.compatibility,
                   !compatibility.platforms.isEmpty
                {
                    Text("Compatibility: \(compatibility.platforms.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Compatibility: unspecified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if preview.requestedPermissions.isEmpty {
                    Text("Permissions: none")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let permissionList = preview.requestedPermissions
                        .map(\.rawValue)
                        .sorted()
                        .joined(separator: ", ")
                    Text("Permissions: \(permissionList)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !preview.warnings.isEmpty {
                    ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func reviewModSource() {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            reviewState = .failed("Enter a mod source URL or local path first.")
            return
        }

        reviewState = .loading
        Task {
            do {
                let preview = try await Task.detached(priority: .userInitiated) {
                    try ModInstallService().preview(source: trimmedSource)
                }.value
                await MainActor.run {
                    reviewState = .loaded(preview)
                }
            } catch {
                await MainActor.run {
                    reviewState = .failed(error.localizedDescription)
                }
            }
        }
    }
}
