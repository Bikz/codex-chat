import CodexChatUI
import CodexMods
import SwiftUI

@MainActor
struct ModsCanvas: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            modsSurface
            Spacer(minLength: 0)
        }
        .navigationTitle("Mods")
        .onAppear {
            model.refreshModsSurface()
        }
    }

    private var header: some View {
        HStack {
            Text("Mods")
                .font(.system(size: tokens.typography.titleSize, weight: .semibold))
            Spacer()

            Button("Refresh") {
                model.refreshModsSurface()
            }
            .buttonStyle(.bordered)

            Button("Open Global Folder") {
                model.revealGlobalModsFolder()
            }
            .buttonStyle(.bordered)

            Button("Open Project Folder") {
                model.revealProjectModsFolder()
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedProject == nil)
        }
        .padding(tokens.spacing.medium)
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
            .padding(tokens.spacing.medium)
        case .loading:
            LoadingStateView(title: "Loading mods…")
                .padding(tokens.spacing.medium)
        case .failed(let message):
            ErrorStateView(title: "Mods unavailable", message: message, actionLabel: "Retry") {
                model.refreshModsSurface()
            }
            .padding(tokens.spacing.medium)
        case .loaded(let surface):
            ScrollView {
                VStack(alignment: .leading, spacing: tokens.spacing.medium) {
                    Text("Precedence: defaults < global mod < project mod.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    globalSection(surface: surface)

                    Divider()

                    projectSection(surface: surface)

                    if let status = model.modStatusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(tokens.spacing.medium)
            }
        }
    }

    private func globalSection(surface: AppModel.ModsSurfaceModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Global Mod")
                    .font(.headline)
                Spacer()
                Button("Create Sample") {
                    model.createSampleGlobalMod()
                }
                .buttonStyle(.bordered)
            }

            Picker("Global mod", selection: Binding<String?>(
                get: { surface.selectedGlobalModPath },
                set: { selection in
                    let mod = surface.globalMods.first(where: { $0.directoryPath == selection })
                    model.setGlobalMod(mod)
                }
            )) {
                Text("None").tag(Optional<String>.none)
                ForEach(surface.globalMods) { mod in
                    Text("\(mod.definition.manifest.name) (\(mod.definition.manifest.version))")
                        .tag(Optional(mod.directoryPath))
                }
            }
            .pickerStyle(.menu)

            if surface.globalMods.isEmpty {
                EmptyStateView(
                    title: "No global mods found",
                    message: "Add a mod directory containing `ui.mod.json` under the global mods folder.",
                    systemImage: "folder"
                )
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: tokens.radius.medium))
    }

    private func projectSection(surface: AppModel.ModsSurfaceModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Project Mod")
                    .font(.headline)
                Spacer()
                Button("Create Sample") {
                    model.createSampleProjectMod()
                }
                .buttonStyle(.bordered)
                .disabled(model.selectedProject == nil)
            }

            if model.selectedProject == nil {
                EmptyStateView(
                    title: "Select a project",
                    message: "Project mods are stored in the project folder under `mods/`.",
                    systemImage: "folder"
                )
            } else {
                Picker("Project mod", selection: Binding<String?>(
                    get: { surface.selectedProjectModPath },
                    set: { selection in
                        let mod = surface.projectMods.first(where: { $0.directoryPath == selection })
                        model.setProjectMod(mod)
                    }
                )) {
                    Text("None").tag(Optional<String>.none)
                    ForEach(surface.projectMods) { mod in
                        Text("\(mod.definition.manifest.name) (\(mod.definition.manifest.version))")
                            .tag(Optional(mod.directoryPath))
                    }
                }
                .pickerStyle(.menu)

                if surface.projectMods.isEmpty {
                    EmptyStateView(
                        title: "No project mods found",
                        message: "Add a mod directory containing `ui.mod.json` under `mods/` in the selected project.",
                        systemImage: "doc.badge.plus"
                    )
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: tokens.radius.medium))
    }
}

