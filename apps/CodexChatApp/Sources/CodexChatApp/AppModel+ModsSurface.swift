import AppKit
import CodexChatCore
import CodexMods
import Foundation

extension AppModel {
    func refreshModsSurface() {
        modsState = .loading
        modsRefreshTask?.cancel()

        modsRefreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                let globalRoot = try Self.globalModsRootPath()
                let projectRoot = selectedProject.map { Self.projectModsRootPath(projectPath: $0.path) }

                let globalMods = try modDiscoveryService.discoverMods(in: globalRoot, scope: .global)
                let projectMods: [DiscoveredUIMod] = if let projectRoot {
                    try modDiscoveryService.discoverMods(in: projectRoot, scope: .project)
                } else {
                    []
                }

                let persistedGlobal = try await preferenceRepository?.getPreference(key: .globalUIModPath)
                let selectedGlobal = Self.normalizedOptionalPath(persistedGlobal)
                let selectedProject = Self.normalizedOptionalPath(selectedProject?.uiModPath)

                let globalOverride = globalMods.first(where: { $0.directoryPath == selectedGlobal })?.definition.theme
                let projectOverride = projectMods.first(where: { $0.directoryPath == selectedProject })?.definition.theme

                var effective = ModThemeOverride()
                if let globalOverride {
                    effective = effective.merged(with: globalOverride)
                }
                if let projectOverride {
                    effective = effective.merged(with: projectOverride)
                }

                effectiveThemeOverride = effective
                modsState = .loaded(
                    ModsSurfaceModel(
                        globalMods: globalMods,
                        projectMods: projectMods,
                        selectedGlobalModPath: selectedGlobal,
                        selectedProjectModPath: selectedProject
                    )
                )

                startModWatchersIfNeeded(globalRootPath: globalRoot, projectRootPath: projectRoot)
            } catch {
                modsState = .failed(error.localizedDescription)
                modStatusMessage = "Failed to load mods: \(error.localizedDescription)"
                appendLog(.error, "Mods refresh failed: \(error.localizedDescription)")
            }
        }
    }

    func setGlobalMod(_ mod: DiscoveredUIMod?) {
        guard let preferenceRepository else {
            modStatusMessage = "Preferences unavailable."
            return
        }

        let value = mod?.directoryPath ?? ""
        Task {
            do {
                try await preferenceRepository.setPreference(key: .globalUIModPath, value: value)
                modStatusMessage = mod == nil ? "Global mod disabled." : "Enabled global mod: \(mod?.definition.manifest.name ?? "")."
                refreshModsSurface()
            } catch {
                modStatusMessage = "Failed to update global mod: \(error.localizedDescription)"
                appendLog(.error, "Update global mod failed: \(error.localizedDescription)")
            }
        }
    }

    func setProjectMod(_ mod: DiscoveredUIMod?) {
        guard let projectRepository,
              let selectedProjectID
        else {
            modStatusMessage = "Select a project first."
            return
        }

        Task {
            do {
                _ = try await projectRepository.updateProjectUIModPath(id: selectedProjectID, uiModPath: mod?.directoryPath)
                try await refreshProjects()
                modStatusMessage = mod == nil ? "Project mod disabled." : "Enabled project mod: \(mod?.definition.manifest.name ?? "")."
                refreshModsSurface()
            } catch {
                modStatusMessage = "Failed to update project mod: \(error.localizedDescription)"
                appendLog(.error, "Update project mod failed: \(error.localizedDescription)")
            }
        }
    }

    func revealGlobalModsFolder() {
        do {
            let path = try Self.globalModsRootPath()
            let url = URL(fileURLWithPath: path, isDirectory: true)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            modStatusMessage = "Unable to reveal global mods folder: \(error.localizedDescription)"
        }
    }

    func revealProjectModsFolder() {
        guard let project = selectedProject else {
            modStatusMessage = "Select a project first."
            return
        }

        let url = URL(fileURLWithPath: Self.projectModsRootPath(projectPath: project.path), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            modStatusMessage = "Unable to reveal project mods folder: \(error.localizedDescription)"
        }
    }

    func createSampleGlobalMod() {
        do {
            let root = try Self.globalModsRootPath()
            let definitionURL = try modDiscoveryService.writeSampleMod(to: root, name: "sample-mod")
            NSWorkspace.shared.activateFileViewerSelecting([definitionURL])
            modStatusMessage = "Created sample global mod."
            refreshModsSurface()
        } catch {
            modStatusMessage = "Failed to create sample mod: \(error.localizedDescription)"
        }
    }

    func createSampleProjectMod() {
        guard let project = selectedProject else {
            modStatusMessage = "Select a project first."
            return
        }

        let root = Self.projectModsRootPath(projectPath: project.path)
        do {
            let definitionURL = try modDiscoveryService.writeSampleMod(to: root, name: "sample-mod")
            NSWorkspace.shared.activateFileViewerSelecting([definitionURL])
            modStatusMessage = "Created sample project mod."
            refreshModsSurface()
        } catch {
            modStatusMessage = "Failed to create sample mod: \(error.localizedDescription)"
        }
    }

    private func startModWatchersIfNeeded(globalRootPath: String, projectRootPath: String?) {
        if globalModsWatcher == nil {
            let watcher = DirectoryWatcher(path: globalRootPath) { [weak self] in
                Task { @MainActor in
                    self?.scheduleModsRefresh()
                }
            }
            do {
                try watcher.start()
                globalModsWatcher = watcher
            } catch {
                appendLog(.warning, "Failed to start global mods watcher: \(error.localizedDescription)")
            }
        }

        if watchedProjectModsRootPath != projectRootPath {
            projectModsWatcher?.stop()
            projectModsWatcher = nil
            watchedProjectModsRootPath = projectRootPath

            guard let projectRootPath else { return }
            let watcher = DirectoryWatcher(path: projectRootPath) { [weak self] in
                Task { @MainActor in
                    self?.scheduleModsRefresh()
                }
            }
            do {
                try watcher.start()
                projectModsWatcher = watcher
            } catch {
                appendLog(.warning, "Failed to start project mods watcher: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleModsRefresh() {
        modsDebounceTask?.cancel()
        modsDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                if Task.isCancelled { return }
                refreshModsSurface()
            } catch {
                return
            }
        }
    }

    static func globalModsRootPath(fileManager: FileManager = .default) throws -> String {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base
            .appendingPathComponent("CodexChat", isDirectory: true)
            .appendingPathComponent("Mods", isDirectory: true)
            .appendingPathComponent("Global", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root.path
    }

    static func projectModsRootPath(projectPath: String) -> String {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("mods", isDirectory: true)
            .standardizedFileURL
            .path
    }

    static func normalizedOptionalPath(_ path: String?) -> String? {
        let trimmed = (path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
