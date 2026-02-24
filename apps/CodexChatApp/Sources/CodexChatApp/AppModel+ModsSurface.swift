import AppKit
import CodexChatCore
import CodexMods
import Foundation

extension AppModel {
    private struct ModsRefreshSnapshot: Sendable {
        let globalRoot: String
        let projectRoot: String?
        let globalMods: [DiscoveredUIMod]
        let projectMods: [DiscoveredUIMod]
        let selectedGlobal: String?
        let selectedProject: String?
    }

    func refreshModsSurface() {
        modsState = .loading
        modsRefreshTask?.cancel()
        extensionCatalogState = .idle

        let selectedProjectPath = selectedProject?.path
        let selectedProjectModPath = selectedProject?.uiModPath
        let modDiscoveryService = modDiscoveryService
        let preferenceRepository = preferenceRepository

        modsRefreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    let globalRoot = try Self.globalModsRootPath()
                    let projectRoot = selectedProjectPath.map { Self.projectModsRootPath(projectPath: $0) }

                    let globalMods = try modDiscoveryService.discoverMods(in: globalRoot, scope: .global)
                    let projectMods: [DiscoveredUIMod] = if let projectRoot {
                        try modDiscoveryService.discoverMods(in: projectRoot, scope: .project)
                    } else {
                        []
                    }

                    let persistedGlobal = try await preferenceRepository?.getPreference(key: .globalUIModPath)
                    let selectedGlobal = Self.normalizedOptionalPath(persistedGlobal)
                    let selectedProject = Self.normalizedOptionalPath(selectedProjectModPath)
                    return ModsRefreshSnapshot(
                        globalRoot: globalRoot,
                        projectRoot: projectRoot,
                        globalMods: globalMods,
                        projectMods: projectMods,
                        selectedGlobal: selectedGlobal,
                        selectedProject: selectedProject
                    )
                }.value

                guard !Task.isCancelled else {
                    return
                }

                let resolved = Self.resolvedThemeOverrides(
                    globalMods: snapshot.globalMods,
                    projectMods: snapshot.projectMods,
                    selectedGlobalPath: snapshot.selectedGlobal,
                    selectedProjectPath: snapshot.selectedProject
                )
                let installRecords = try await extensionInstallRepository?.list() ?? []
                let enabledModIDs = Self.resolveEnabledModIDs(
                    globalMods: snapshot.globalMods,
                    projectMods: snapshot.projectMods,
                    selectedGlobalPath: snapshot.selectedGlobal,
                    selectedProjectPath: snapshot.selectedProject,
                    selectedProjectID: selectedProjectID,
                    installRecords: installRecords
                )
                effectiveThemeOverride = resolved.light
                effectiveDarkThemeOverride = resolved.dark
                modsState = .loaded(
                    ModsSurfaceModel(
                        globalMods: snapshot.globalMods,
                        projectMods: snapshot.projectMods,
                        selectedGlobalModPath: snapshot.selectedGlobal,
                        selectedProjectModPath: snapshot.selectedProject,
                        enabledGlobalModIDs: enabledModIDs.global,
                        enabledProjectModIDs: enabledModIDs.project
                    )
                )
                syncActiveExtensions(
                    globalMods: snapshot.globalMods,
                    projectMods: snapshot.projectMods,
                    selectedGlobalPath: snapshot.selectedGlobal,
                    selectedProjectPath: snapshot.selectedProject,
                    installRecords: installRecords
                )
                let modIDs = (snapshot.globalMods + snapshot.projectMods).map(\.definition.manifest.id)
                await refreshAutomationHealthSummaries(for: modIDs)

                startModWatchersIfNeeded(globalRootPath: snapshot.globalRoot, projectRootPath: snapshot.projectRoot)
            } catch {
                modsState = .failed(error.localizedDescription)
                modStatusMessage = "Failed to load mods: \(error.localizedDescription)"
                activeModsBarSlot = nil
                activeExtensionHooks = []
                activeExtensionAutomations = []
                extensionAutomationHealthByModID = [:]
                Task { await stopExtensionAutomations() }
                appendLog(.error, "Mods refresh failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshModCatalog() async {
        extensionCatalogState = .idle
    }

    func setGlobalMod(_ mod: DiscoveredUIMod?) {
        guard let preferenceRepository else {
            modStatusMessage = "Preferences unavailable."
            return
        }

        if let mod,
           let blockedReason = executableModBlockedReason(for: mod)
        {
            modStatusMessage = blockedReason
            return
        }

        let value = mod?.directoryPath ?? ""
        Task {
            do {
                try await preferenceRepository.setPreference(key: .globalUIModPath, value: value)
                try await updateExtensionInstallEnablement(
                    scope: .global,
                    projectID: nil,
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

        if let mod,
           let blockedReason = executableModBlockedReason(for: mod)
        {
            modStatusMessage = blockedReason
            return
        }

        Task {
            do {
                _ = try await projectRepository.updateProjectUIModPath(id: selectedProjectID, uiModPath: mod?.directoryPath)
                try await updateExtensionInstallEnablement(
                    scope: .project,
                    projectID: selectedProjectID,
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

    func setInstalledModEnabled(
        _ mod: DiscoveredUIMod,
        scope: ExtensionInstallScope,
        enabled: Bool
    ) {
        guard let extensionInstallRepository else {
            modStatusMessage = "Extension install repository unavailable."
            return
        }

        Task {
            do {
                let projectID = installProjectID(for: scope)
                let installs = try await extensionInstallRepository.list()
                let existing = installs.first(where: { record in
                    guard record.scope == scope,
                          record.modID == mod.definition.manifest.id
                    else {
                        return false
                    }
                    if scope == .project {
                        return record.projectID == projectID
                    }
                    return true
                })

                var next = existing ?? ExtensionInstallRecord(
                    id: extensionInstallRecordID(
                        scope: scope,
                        projectID: projectID,
                        modID: mod.definition.manifest.id
                    ),
                    modID: mod.definition.manifest.id,
                    scope: scope,
                    projectID: projectID,
                    sourceURL: existing?.sourceURL,
                    installedPath: mod.directoryPath,
                    enabled: enabled
                )
                next.installedPath = mod.directoryPath
                next.enabled = enabled
                _ = try await extensionInstallRepository.upsert(next)

                if !enabled {
                    switch scope {
                    case .global:
                        if case let .loaded(surface) = modsState,
                           surface.selectedGlobalModPath == mod.directoryPath
                        {
                            try await preferenceRepository?.setPreference(key: .globalUIModPath, value: "")
                        }
                    case .project:
                        if case let .loaded(surface) = modsState,
                           surface.selectedProjectModPath == mod.directoryPath,
                           let selectedProjectID,
                           let projectRepository
                        {
                            _ = try await projectRepository.updateProjectUIModPath(id: selectedProjectID, uiModPath: nil)
                            try await refreshProjects()
                        }
                    }
                }

                modStatusMessage = enabled
                    ? "Enabled mod runtime: \(mod.definition.manifest.name)."
                    : "Disabled mod runtime: \(mod.definition.manifest.name)."
                refreshModsSurface()
            } catch {
                modStatusMessage = "Failed updating mod enablement: \(error.localizedDescription)"
                appendLog(.error, "Mod enablement update failed: \(error.localizedDescription)")
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
        if trimmed.hasPrefix("git@github.com:") {
            return true
        }
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return false
        }
        return host == "github.com"
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

        let blockedCapabilities = blockedCapabilitiesForModInstall(source: trimmedSource, scope: scope)
        if !blockedCapabilities.isEmpty {
            let blockedList = blockedCapabilities.map(\.rawValue).sorted().joined(separator: ", ")
            modStatusMessage = "Mod install blocked in untrusted project: \(blockedList)."
            appendLog(.warning, "Mod install blocked in untrusted project (\(blockedList)) for source \(trimmedSource)")
            return
        }

        isModOperationInProgress = true
        modStatusMessage = nil

        Task {
            defer { isModOperationInProgress = false }

            do {
                let installProjectID: UUID? = switch scope {
                case .global:
                    nil
                case .project:
                    selectedProjectID
                }
                let rootPath = try installRootPath(for: scope)
                let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
                try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
                let installService = ModInstallService()
                let installResult = try installService.install(
                    source: trimmedSource,
                    destinationRootURL: rootURL
                )

                let discovered = try modDiscoveryService.discoverMods(
                    in: rootPath,
                    scope: mapInstallScope(scope)
                )

                guard let installedMod = discovered.first(where: { $0.directoryPath == installResult.installedDirectoryPath }) else {
                    throw NSError(
                        domain: "CodexChat.ModInstall",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Installed mod was not discoverable after copy."]
                    )
                }

                if let extensionInstallRepository {
                    let allowExecutable = canRunExecutableModFeatures(for: installedMod)
                    _ = try await extensionInstallRepository.upsert(
                        ExtensionInstallRecord(
                            id: extensionInstallRecordID(
                                scope: scope,
                                projectID: installProjectID,
                                modID: installResult.definition.manifest.id
                            ),
                            modID: installResult.definition.manifest.id,
                            scope: scope,
                            projectID: installProjectID,
                            sourceURL: trimmedSource,
                            installedPath: installResult.installedDirectoryPath,
                            enabled: allowExecutable
                        )
                    )
                }

                if let blockedReason = executableModBlockedReason(for: installedMod) {
                    switch scope {
                    case .global:
                        setGlobalMod(nil)
                    case .project:
                        setProjectMod(nil)
                    }
                    modStatusMessage = "Installed \(installResult.definition.manifest.name), but it is disabled. \(blockedReason)"
                } else {
                    switch scope {
                    case .global:
                        setGlobalMod(installedMod)
                    case .project:
                        setProjectMod(installedMod)
                    }
                }

                var permissionHint = ""
                if !installResult.requestedPermissions.isEmpty {
                    let keys = installResult.requestedPermissions
                        .map(\.rawValue)
                        .sorted()
                        .joined(separator: ", ")
                    permissionHint = " First run requires permissions: \(keys)."
                }
                let warningHint = installResult.warnings.isEmpty ? "" : " \(installResult.warnings.joined(separator: " "))"

                if executableModBlockedReason(for: installedMod) == nil {
                    modStatusMessage = "Installed and enabled mod: \(installResult.definition.manifest.name).\(permissionHint)\(warningHint)"
                }
                appendLog(.info, "Installed mod \(installResult.definition.manifest.id) from \(trimmedSource)")
            } catch {
                if let details = Self.extensibilityProcessFailureDetails(from: error) {
                    recordExtensibilityDiagnostic(surface: "mods", operation: "install", details: details)
                    modStatusMessage = "Mod install failed (\(details.kind.label)): \(details.summary)"
                    appendLog(
                        .error,
                        "Mod install process failure [\(details.kind.rawValue)] (\(details.command)): \(details.summary)"
                    )
                } else {
                    modStatusMessage = "Mod install failed: \(error.localizedDescription)"
                    appendLog(.error, "Mod install failed: \(error.localizedDescription)")
                }
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

    func updateInstalledMod(_ mod: DiscoveredUIMod, scope: ExtensionInstallScope) {
        guard let extensionInstallRepository else {
            modStatusMessage = "Extension install repository unavailable."
            return
        }

        isModOperationInProgress = true
        modStatusMessage = nil

        Task {
            defer { isModOperationInProgress = false }

            do {
                let installProjectID = installProjectID(for: scope)
                let installs = try await extensionInstallRepository.list()
                guard let record = installs.first(where: {
                    $0.scope == scope
                        && $0.modID == mod.definition.manifest.id
                        && $0.projectID == installProjectID
                }) else {
                    throw NSError(
                        domain: "CodexChat.ModInstall",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "No install metadata found for \(mod.definition.manifest.name)."]
                    )
                }
                guard let source = record.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else {
                    throw NSError(
                        domain: "CodexChat.ModInstall",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Cannot update \(mod.definition.manifest.name): original source URL is missing."]
                    )
                }

                let blockedCapabilities = blockedCapabilitiesForModInstall(source: source, scope: scope)
                if !blockedCapabilities.isEmpty {
                    let blockedList = blockedCapabilities.map(\.rawValue).sorted().joined(separator: ", ")
                    modStatusMessage = "Mod update blocked in untrusted project: \(blockedList)."
                    appendLog(.warning, "Mod update blocked in untrusted project (\(blockedList)) for source \(source)")
                    return
                }

                let installService = ModInstallService()
                let result = try installService.update(
                    source: source,
                    existingInstallURL: URL(fileURLWithPath: record.installedPath, isDirectory: true)
                )

                var updatedRecord = record
                updatedRecord.installedPath = result.installedDirectoryPath
                updatedRecord.enabled = true
                _ = try await extensionInstallRepository.upsert(updatedRecord)

                modStatusMessage = "Updated mod: \(result.definition.manifest.name)."
                refreshModsSurface()
            } catch {
                if let details = Self.extensibilityProcessFailureDetails(from: error) {
                    recordExtensibilityDiagnostic(surface: "mods", operation: "update", details: details)
                    modStatusMessage = "Mod update failed (\(details.kind.label)): \(details.summary)"
                    appendLog(
                        .error,
                        "Mod update process failure [\(details.kind.rawValue)] (\(details.command)): \(details.summary)"
                    )
                } else {
                    modStatusMessage = "Mod update failed: \(error.localizedDescription)"
                    appendLog(.error, "Mod update failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func blockedCapabilitiesForModInstall(
        source: String,
        scope: ExtensionInstallScope
    ) -> Set<ExtensibilityCapability> {
        guard scope == .project else {
            return []
        }
        return blockedExtensibilityCapabilities(
            for: requiredExtensibilityCapabilitiesForModInstall(source: source),
            projectID: selectedProjectID
        )
    }

    func requiredExtensibilityCapabilitiesForModInstall(source: String) -> Set<ExtensibilityCapability> {
        var required: Set<ExtensibilityCapability> = [.filesystemWrite]
        if modInstallLikelyRequiresNetwork(source) {
            required.insert(.network)
        }
        return required
    }

    func modInstallLikelyRequiresNetwork(_ source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }

        if FileManager.default.fileExists(atPath: trimmed) {
            return false
        }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("./") || trimmed.hasPrefix("../") || trimmed.hasPrefix("~/") {
            return false
        }

        if trimmed.hasPrefix("file://") {
            return false
        }

        if trimmed.hasPrefix("git@") || trimmed.contains("://") {
            return true
        }

        return !trimmed.hasPrefix(".")
    }

    func uninstallInstalledMod(_ mod: DiscoveredUIMod, scope: ExtensionInstallScope) {
        guard let extensionInstallRepository else {
            modStatusMessage = "Extension install repository unavailable."
            return
        }

        isModOperationInProgress = true
        modStatusMessage = nil

        Task {
            defer { isModOperationInProgress = false }

            do {
                let installProjectID = installProjectID(for: scope)
                let installs = try await extensionInstallRepository.list()
                let matching = installs.filter {
                    $0.scope == scope
                        && $0.modID == mod.definition.manifest.id
                        && $0.projectID == installProjectID
                }

                for record in matching {
                    if FileManager.default.fileExists(atPath: record.installedPath) {
                        try? FileManager.default.removeItem(atPath: record.installedPath)
                    }
                    try await extensionInstallRepository.delete(id: record.id)
                }

                let currentSelection: (global: String?, project: String?) = {
                    guard case let .loaded(surface) = modsState else { return (nil, nil) }
                    return (surface.selectedGlobalModPath, surface.selectedProjectModPath)
                }()

                switch scope {
                case .global:
                    if currentSelection.global == mod.directoryPath {
                        try await preferenceRepository?.setPreference(key: .globalUIModPath, value: "")
                    }
                case .project:
                    if currentSelection.project == mod.directoryPath,
                       let selectedProjectID,
                       let projectRepository
                    {
                        _ = try await projectRepository.updateProjectUIModPath(id: selectedProjectID, uiModPath: nil)
                    }
                }

                modStatusMessage = "Uninstalled mod: \(mod.definition.manifest.name)."
                refreshModsSurface()
            } catch {
                modStatusMessage = "Mod uninstall failed: \(error.localizedDescription)"
                appendLog(.error, "Mod uninstall failed: \(error.localizedDescription)")
            }
        }
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

    nonisolated static func globalModsRootPath(fileManager: FileManager = .default) throws -> String {
        let storagePaths = CodexChatStoragePaths.current(fileManager: fileManager)
        let root = storagePaths.globalModsURL
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root.path
    }

    nonisolated static func projectModsRootPath(projectPath: String) -> String {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("mods", isDirectory: true)
            .standardizedFileURL
            .path
    }

    nonisolated static func normalizedOptionalPath(_ path: String?) -> String? {
        let trimmed = (path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    nonisolated static func resolveEnabledModIDs(
        globalMods: [DiscoveredUIMod],
        projectMods: [DiscoveredUIMod],
        selectedGlobalPath: String?,
        selectedProjectPath: String?,
        selectedProjectID: UUID?,
        installRecords: [ExtensionInstallRecord]
    ) -> (global: Set<String>, project: Set<String>) {
        let globalIDs = Set(globalMods.map(\.definition.manifest.id))
        let projectIDs = Set(projectMods.map(\.definition.manifest.id))

        var enabledGlobal: Set<String> = []
        var enabledProject: Set<String> = []

        for record in installRecords where record.enabled {
            switch record.scope {
            case .global:
                if globalIDs.contains(record.modID) {
                    enabledGlobal.insert(record.modID)
                }
            case .project:
                guard record.projectID == selectedProjectID,
                      projectIDs.contains(record.modID)
                else {
                    continue
                }
                enabledProject.insert(record.modID)
            }
        }

        for mod in globalMods {
            let normalizedPath = NSString(string: mod.directoryPath).standardizingPath
            if mod.definition.manifest.id.lowercased().hasPrefix("codexchat.")
                || normalizedPath.contains("/mods/first-party/")
            {
                enabledGlobal.insert(mod.definition.manifest.id)
            }
        }
        for mod in projectMods {
            let normalizedPath = NSString(string: mod.directoryPath).standardizingPath
            if mod.definition.manifest.id.lowercased().hasPrefix("codexchat.")
                || normalizedPath.contains("/mods/first-party/")
            {
                enabledProject.insert(mod.definition.manifest.id)
            }
        }

        if let selectedGlobalPath,
           let selectedGlobal = globalMods.first(where: { $0.directoryPath == selectedGlobalPath }),
           installRecords.first(where: { $0.scope == .global && $0.modID == selectedGlobal.definition.manifest.id }) == nil
        {
            enabledGlobal.insert(selectedGlobal.definition.manifest.id)
        }

        if let selectedProjectPath,
           let selectedProject = projectMods.first(where: { $0.directoryPath == selectedProjectPath }),
           installRecords.first(where: {
               $0.scope == .project
                   && $0.projectID == selectedProjectID
                   && $0.modID == selectedProject.definition.manifest.id
           }) == nil
        {
            enabledProject.insert(selectedProject.definition.manifest.id)
        }

        return (enabledGlobal, enabledProject)
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

    private func installProjectID(for scope: ExtensionInstallScope) -> UUID? {
        switch scope {
        case .global:
            nil
        case .project:
            selectedProjectID
        }
    }

    private func updateExtensionInstallEnablement(
        scope: ExtensionInstallScope,
        projectID: UUID?,
        enabledModID: String?
    ) async throws {
        guard let extensionInstallRepository,
              let enabledModID = enabledModID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !enabledModID.isEmpty
        else { return }

        let installs = try await extensionInstallRepository.list()
        for record in installs where record.scope == scope {
            if scope == .project, record.projectID != projectID {
                continue
            }
            guard record.modID == enabledModID,
                  !record.enabled
            else {
                continue
            }
            var next = record
            next.enabled = true
            _ = try await extensionInstallRepository.upsert(next)
        }
    }

    private func extensionInstallRecordID(
        scope: ExtensionInstallScope,
        projectID: UUID?,
        modID: String
    ) -> String {
        switch scope {
        case .global:
            return "global:\(modID)"
        case .project:
            let projectKey = projectID?.uuidString.lowercased() ?? "unknown-project"
            return "project:\(projectKey):\(modID)"
        }
    }
}
