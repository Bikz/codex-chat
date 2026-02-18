import AppKit
import CodexChatCore
import CodexMods
import Foundation

extension AppModel {
    func refreshModsSurface() {
        modsState = .loading
        modsRefreshTask?.cancel()
        if case .idle = extensionCatalogState {
            extensionCatalogState = .loading
        }

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

                let resolved = Self.resolvedThemeOverrides(
                    globalMods: globalMods,
                    projectMods: projectMods,
                    selectedGlobalPath: selectedGlobal,
                    selectedProjectPath: selectedProject
                )
                effectiveThemeOverride = resolved.light
                effectiveDarkThemeOverride = resolved.dark
                modsState = .loaded(
                    ModsSurfaceModel(
                        globalMods: globalMods,
                        projectMods: projectMods,
                        selectedGlobalModPath: selectedGlobal,
                        selectedProjectModPath: selectedProject
                    )
                )
                syncActiveExtensions(
                    globalMods: globalMods,
                    projectMods: projectMods,
                    selectedGlobalPath: selectedGlobal,
                    selectedProjectPath: selectedProject
                )
                await refreshModCatalog()

                startModWatchersIfNeeded(globalRootPath: globalRoot, projectRootPath: projectRoot)
            } catch {
                modsState = .failed(error.localizedDescription)
                modStatusMessage = "Failed to load mods: \(error.localizedDescription)"
                activeRightInspectorSlot = nil
                activeExtensionHooks = []
                activeExtensionAutomations = []
                Task { await stopExtensionAutomations() }
                appendLog(.error, "Mods refresh failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshModCatalog() async {
        do {
            let listings = try await modCatalogProvider.listAvailableMods()
            extensionCatalogState = .loaded(listings)
        } catch {
            if case .loaded = extensionCatalogState {
                return
            }
            extensionCatalogState = .failed(error.localizedDescription)
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
                try await updateExtensionInstallEnablement(
                    scope: .global,
                    enabledModID: mod?.definition.manifest.id
                )
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
                try await updateExtensionInstallEnablement(
                    scope: .project,
                    enabledModID: mod?.definition.manifest.id
                )
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

    func isTrustedModSource(_ source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if FileManager.default.fileExists(atPath: trimmed) {
            return true
        }
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return false
        }
        let trustedHosts = ["github.com", "gitlab.com", "bitbucket.org"]
        return trustedHosts.contains(host)
    }

    func installMod(
        source: String,
        scope: ExtensionInstallScope
    ) {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            modStatusMessage = "Enter a mod source URL or local path."
            return
        }

        isModOperationInProgress = true
        modStatusMessage = nil

        Task {
            defer { isModOperationInProgress = false }

            do {
                let rootPath = try installRootPath(for: scope)
                let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
                try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

                let staged = try stageModSource(trimmedSource)
                defer {
                    if let cleanupURL = staged.cleanupURL {
                        try? FileManager.default.removeItem(at: cleanupURL)
                    }
                }

                let modDirectory = try resolveModDirectory(from: staged.modRootURL)
                let definitionURL = modDirectory.appendingPathComponent("ui.mod.json", isDirectory: false)
                let definitionData = try Data(contentsOf: definitionURL)
                let definition = try JSONDecoder().decode(UIModDefinition.self, from: definitionData)

                let destinationName = sanitizedModDirectoryName(from: definition.manifest.id)
                let destinationURL = uniqueModDestinationURL(
                    in: rootURL,
                    preferredName: destinationName
                )
                try FileManager.default.copyItem(at: modDirectory, to: destinationURL)

                let discovered = try modDiscoveryService.discoverMods(
                    in: rootPath,
                    scope: mapInstallScope(scope)
                )

                guard let installedMod = discovered.first(where: { $0.directoryPath == destinationURL.path }) else {
                    throw NSError(
                        domain: "CodexChat.ModInstall",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Installed mod was not discoverable after copy."]
                    )
                }

                if let extensionInstallRepository {
                    _ = try await extensionInstallRepository.upsert(
                        ExtensionInstallRecord(
                            id: "\(scope.rawValue):\(definition.manifest.id)",
                            modID: definition.manifest.id,
                            scope: scope,
                            sourceURL: trimmedSource,
                            installedPath: destinationURL.path,
                            enabled: true
                        )
                    )
                }

                switch scope {
                case .global:
                    setGlobalMod(installedMod)
                case .project:
                    setProjectMod(installedMod)
                }

                modStatusMessage = "Installed and enabled mod: \(definition.manifest.name)."
                appendLog(.info, "Installed mod \(definition.manifest.id) from \(trimmedSource)")
            } catch {
                modStatusMessage = "Mod install failed: \(error.localizedDescription)"
                appendLog(.error, "Mod install failed: \(error.localizedDescription)")
            }
        }
    }

    func installCatalogMod(_ listing: CatalogModListing, scope: ExtensionInstallScope) {
        let source = listing.downloadURL ?? listing.repositoryURL
        guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            modStatusMessage = "Catalog listing \(listing.name) has no install source URL."
            return
        }
        installMod(source: source, scope: scope)
    }

    nonisolated static func resolvedThemeOverrides(
        globalMods: [DiscoveredUIMod],
        projectMods: [DiscoveredUIMod],
        selectedGlobalPath: String?,
        selectedProjectPath: String?
    ) -> (light: ModThemeOverride, dark: ModThemeOverride) {
        let globalMod = globalMods.first(where: { $0.directoryPath == selectedGlobalPath })
        let projectMod = projectMods.first(where: { $0.directoryPath == selectedProjectPath })

        var light = ModThemeOverride()
        if let globalTheme = globalMod?.definition.theme {
            light = light.merged(with: globalTheme)
        }
        if let projectTheme = projectMod?.definition.theme {
            light = light.merged(with: projectTheme)
        }

        var darkVariant = ModThemeOverride()
        if let globalDarkTheme = globalMod?.definition.darkTheme {
            darkVariant = darkVariant.merged(with: globalDarkTheme)
        }
        if let projectDarkTheme = projectMod?.definition.darkTheme {
            darkVariant = darkVariant.merged(with: projectDarkTheme)
        }

        return (light, light.resolvedDarkOverride(using: darkVariant))
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
        let storagePaths = CodexChatStoragePaths.current(fileManager: fileManager)
        let root = storagePaths.globalModsURL
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

    private func installRootPath(for scope: ExtensionInstallScope) throws -> String {
        switch scope {
        case .global:
            return try Self.globalModsRootPath()
        case .project:
            guard let project = selectedProject else {
                throw NSError(
                    domain: "CodexChat.ModInstall",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Select a project to install a project-scoped mod."]
                )
            }
            return Self.projectModsRootPath(projectPath: project.path)
        }
    }

    private func mapInstallScope(_ scope: ExtensionInstallScope) -> ModScope {
        switch scope {
        case .global:
            .global
        case .project:
            .project
        }
    }

    private struct StagedModSource {
        let modRootURL: URL
        let cleanupURL: URL?
    }

    private func stageModSource(_ source: String) throws -> StagedModSource {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: source) {
            return StagedModSource(
                modRootURL: URL(fileURLWithPath: source, isDirectory: true).standardizedFileURL,
                cleanupURL: nil
            )
        }

        if let fileURL = URL(string: source), fileURL.isFileURL {
            return StagedModSource(
                modRootURL: fileURL.standardizedFileURL,
                cleanupURL: nil
            )
        }

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("codexchat-mod-install-\(UUID().uuidString)", isDirectory: true)

        let process = Process()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "clone", "--depth", "1", source, tempRoot.path]
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detail: String = if let stderr, !stderr.isEmpty {
                stderr
            } else {
                "git clone failed."
            }
            throw NSError(
                domain: "CodexChat.ModInstall",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: detail]
            )
        }

        return StagedModSource(modRootURL: tempRoot, cleanupURL: tempRoot)
    }

    private func resolveModDirectory(from rootURL: URL) throws -> URL {
        let fileManager = FileManager.default

        let directDefinition = rootURL.appendingPathComponent("ui.mod.json", isDirectory: false)
        if fileManager.fileExists(atPath: directDefinition.path) {
            return rootURL
        }

        let children = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let candidates = children.filter { child in
            ((try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
                && fileManager.fileExists(atPath: child.appendingPathComponent("ui.mod.json", isDirectory: false).path)
        }

        if candidates.count == 1, let first = candidates.first {
            return first
        }

        throw NSError(
            domain: "CodexChat.ModInstall",
            code: 4,
            userInfo: [
                NSLocalizedDescriptionKey: "Source must contain exactly one mod folder with `ui.mod.json`.",
            ]
        )
    }

    private func sanitizedModDirectoryName(from manifestID: String) -> String {
        let trimmed = manifestID.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "mod" : trimmed
        let safe = fallback.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "-",
            options: .regularExpression
        )
        return safe.isEmpty ? "mod" : safe
    }

    private func uniqueModDestinationURL(in rootURL: URL, preferredName: String) -> URL {
        let fileManager = FileManager.default
        var candidate = rootURL.appendingPathComponent(preferredName, isDirectory: true)
        var index = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = rootURL.appendingPathComponent("\(preferredName)-\(index)", isDirectory: true)
            index += 1
        }

        return candidate
    }

    private func updateExtensionInstallEnablement(
        scope: ExtensionInstallScope,
        enabledModID: String?
    ) async throws {
        guard let extensionInstallRepository else { return }
        let installs = try await extensionInstallRepository.list()
        for record in installs where record.scope == scope {
            var next = record
            next.enabled = (record.modID == enabledModID)
            _ = try await extensionInstallRepository.upsert(next)
        }
    }
}
