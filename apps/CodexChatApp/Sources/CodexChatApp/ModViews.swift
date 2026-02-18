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

                    modGuideSection
                    globalSection(surface: surface)
                    projectSection(surface: surface)
                    catalogSection

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
                    Text("Global Mod")
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
                        message: "Add a mod directory containing `ui.mod.json` under the global mods folder.",
                        systemImage: "folder"
                    )
                } else {
                    LazyVGrid(columns: modCardColumns, alignment: .leading, spacing: 10) {
                        ForEach(surface.globalMods) { mod in
                            modOptionCard(
                                mod: mod,
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
                    Label("Create and Share Mods", systemImage: "sparkles.rectangle.stack")
                        .font(.title3.weight(.semibold))

                    Spacer()

                    Text("ui.mod.json")
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
                    text: "Edit the generated `ui.mod.json` and set manifest fields, then tune theme tokens."
                )
                guideStep(
                    number: 3,
                    text: "For sharing, commit that mod directory to any git repository and share the repo URL."
                )
                guideStep(
                    number: 4,
                    text: "Others can clone that folder into Global Mods or into `<project>/mods`, then select it here."
                )
            }
        }
    }

    private func projectSection(surface: AppModel.ModsSurfaceModel) -> some View {
        SkillsModsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Project Mod")
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
                        message: "Add a mod directory containing `ui.mod.json` under `mods/` in the selected project.",
                        systemImage: "doc.badge.plus"
                    )
                } else {
                    LazyVGrid(columns: modCardColumns, alignment: .leading, spacing: 10) {
                        ForEach(surface.projectMods) { mod in
                            modOptionCard(
                                mod: mod,
                                isSelected: surface.selectedProjectModPath == mod.directoryPath,
                                onSelect: { model.setProjectMod(mod) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func modOptionCard(mod: DiscoveredUIMod, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(mod.definition.manifest.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color(hex: tokens.palette.accentHex))
                    }
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
        }
        .buttonStyle(.plain)
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

    @ViewBuilder
    private var catalogSection: some View {
        switch model.extensionCatalogState {
        case .idle:
            EmptyView()
        case .loading:
            SkillsModsCard {
                LoadingStateView(title: "Loading catalog…")
            }
        case let .failed(message):
            SkillsModsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Catalog unavailable")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case let .loaded(listings):
            if listings.isEmpty {
                EmptyView()
            } else {
                SkillsModsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Curated Catalog")
                            .font(.title3.weight(.semibold))

                        ForEach(listings) { listing in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(listing.name)
                                        .font(.headline)
                                    Text("v\(listing.version)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if let summary = listing.summary, !summary.isEmpty {
                                        Text(summary)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    if let trustMetadata = listing.trustMetadata, !trustMetadata.isEmpty {
                                        Text(trustMetadata)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 0)

                                Menu {
                                    Button("Install to Project") {
                                        model.installCatalogMod(listing, scope: .project)
                                    }
                                    .disabled(model.selectedProject == nil)

                                    Button("Install Globally") {
                                        model.installCatalogMod(listing, scope: .global)
                                    }
                                } label: {
                                    Label("Install", systemImage: "square.and.arrow.down")
                                }
                                .menuStyle(.borderlessButton)
                            }
                            .padding(.vertical, 4)

                            if listing.id != listings.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
}

struct InstallModSheet: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool

    @State private var source = ""
    @State private var scope: ExtensionInstallScope = .project
    @State private var trustConfirmed = false

    private var isTrustedSource: Bool {
        model.isTrustedModSource(source)
    }

    private var canSubmit: Bool {
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (isTrustedSource || trustConfirmed)
            && (scope == .global || model.selectedProject != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Install Mod")
                .font(.title3.weight(.semibold))

            Text("Install from a git URL or a local folder containing `ui.mod.json`. Installed mods are enabled immediately.")
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
        }
    }
}
