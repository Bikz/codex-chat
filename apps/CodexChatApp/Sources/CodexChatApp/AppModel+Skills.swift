import AppKit
import CodexChatCore
import CodexSkills
import Foundation

extension AppModel {
    var isComposerSkillAutocompleteActive: Bool {
        composerSkillTokenMatch(in: composerText) != nil
    }

    var composerSkillAutocompleteSuggestions: [SkillListItem] {
        guard let tokenMatch = composerSkillTokenMatch(in: composerText) else {
            return []
        }

        let availableSkills = skills.filter(\.isEnabledForSelectedProject)
        let sortedSkills = sortedComposerSkillSuggestions(availableSkills)
        guard !tokenMatch.query.isEmpty else {
            return sortedSkills
        }

        return sortedSkills.filter { skill in
            composerSkill(skill, matches: tokenMatch.query)
        }
    }

    func refreshSkillsSurface() {
        Task {
            do {
                try await refreshSkills()
                await refreshSkillsCatalog()
            } catch {
                skillsState = .failed(error.localizedDescription)
                skillStatusMessage = "Failed to refresh skills: \(error.localizedDescription)"
                appendLog(.error, "Refresh skills failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshSkillsCatalog() async {
        availableSkillsCatalogState = .loading

        do {
            let listings = try await skillCatalogProvider.listAvailableSkills()
            availableSkillsCatalogState = .loaded(listings)
        } catch {
            availableSkillsCatalogState = .failed(error.localizedDescription)
            skillStatusMessage = "Catalog fetch failed: \(error.localizedDescription)"
            appendLog(.warning, "Catalog fetch failed: \(error.localizedDescription)")
        }
    }

    func isTrustedSkillSource(_ source: String) -> Bool {
        skillCatalogService.isTrustedSource(source)
    }

    func installSkill(
        source: String,
        scope: SkillInstallScope,
        installer: SkillInstallerKind,
        projectIDs: [UUID]? = nil,
        allowUntrustedSource: Bool = false,
        pinnedRef: String? = nil
    ) {
        if scope == .project, projectIDs?.isEmpty ?? true, selectedProject == nil {
            skillStatusMessage = "Select a project before installing to selected projects."
            return
        }

        let blockedCapabilities = blockedCapabilitiesForSkillInstall(
            source: source,
            scope: scope,
            installer: installer
        )
        if !blockedCapabilities.isEmpty {
            let blockedList = blockedCapabilities.map(\.rawValue).sorted().joined(separator: ", ")
            skillStatusMessage = "Skill install blocked in untrusted project: \(blockedList)."
            appendLog(.warning, "Skill install blocked in untrusted project (\(blockedList)) for source \(source)")
            return
        }

        isSkillOperationInProgress = true
        skillStatusMessage = nil

        let request = SkillInstallRequest(
            source: source,
            scope: .global,
            projectPath: nil,
            installer: installer,
            pinnedRef: pinnedRef,
            allowUntrustedSource: allowUntrustedSource
        )

        Task {
            defer { isSkillOperationInProgress = false }
            do {
                let result = try skillCatalogService.installSkill(request)
                try await registerInstalledSkill(
                    source: source,
                    installer: installer,
                    requestedScope: scope,
                    selectedProjectIDsOverride: projectIDs,
                    installedPath: result.installedPath
                )
                try await refreshSkills()
                await refreshSkillsCatalog()
                skillStatusMessage = "Installed skill to \(result.installedPath)."
                appendLog(.info, "Installed skill from \(source)")
            } catch {
                if let details = Self.extensibilityProcessFailureDetails(from: error) {
                    recordExtensibilityDiagnostic(surface: "skills", operation: "install", details: details)
                    skillStatusMessage = "Skill install failed (\(details.kind.label)): \(details.summary)"
                    appendLog(
                        .error,
                        "Skill install process failure [\(details.kind.rawValue)] (\(details.command)): \(details.summary)"
                    )
                } else {
                    skillStatusMessage = "Skill install failed: \(error.localizedDescription)"
                    appendLog(.error, "Skill install failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func installCatalogSkill(
        _ listing: CatalogSkillListing,
        scope: SkillInstallScope,
        projectIDs: [UUID]? = nil
    ) {
        let source = listing.installSource ?? listing.repositoryURL
        guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            skillStatusMessage = "Catalog listing \(listing.name) has no install source URL."
            return
        }

        installSkill(source: source, scope: scope, installer: .git, projectIDs: projectIDs)
    }

    func updateSkill(_ item: SkillListItem) {
        isSkillOperationInProgress = true
        skillStatusMessage = nil

        Task {
            defer { isSkillOperationInProgress = false }
            do {
                switch item.updateCapability {
                case .gitUpdate:
                    _ = try skillCatalogService.updateSkill(at: item.skill.skillPath)
                    skillStatusMessage = "Updated \(item.skill.name)."
                    appendLog(.info, "Updated skill \(item.skill.name)")
                case .reinstall:
                    _ = try skillCatalogService.reinstallSkill(item.skill)
                    skillStatusMessage = "Reinstalled \(item.skill.name)."
                    appendLog(.info, "Reinstalled skill \(item.skill.name)")
                case .unavailable:
                    skillStatusMessage = "Update unavailable: source metadata missing"
                    appendLog(.warning, "Update unavailable for skill \(item.skill.name): source metadata missing")
                    return
                }

                try await refreshSkills()
                await refreshSkillsCatalog()
            } catch {
                if let details = Self.extensibilityProcessFailureDetails(from: error) {
                    recordExtensibilityDiagnostic(surface: "skills", operation: "update", details: details)
                    skillStatusMessage = "Skill update failed (\(details.kind.label)): \(details.summary)"
                    appendLog(
                        .error,
                        "Skill update process failure [\(details.kind.rawValue)] (\(details.command)): \(details.summary)"
                    )
                } else {
                    skillStatusMessage = "Skill update failed: \(error.localizedDescription)"
                    appendLog(.error, "Skill update failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func uninstallSkill(_ item: SkillListItem) {
        isSkillOperationInProgress = true
        skillStatusMessage = nil

        Task {
            defer { isSkillOperationInProgress = false }
            do {
                try await removeSkillInstallRecordAndLinks(item, uninstallSharedSkill: true)
                try await refreshSkills()
                await refreshSkillsCatalog()
                if selectedSkillIDForComposer == item.id {
                    selectedSkillIDForComposer = nil
                }
                skillStatusMessage = "Removed \(item.skill.name)."
                appendLog(.info, "Removed skill \(item.skill.name)")
            } catch {
                skillStatusMessage = "Failed to remove skill: \(error.localizedDescription)"
                appendLog(.error, "Skill remove failed for \(item.skill.name): \(error.localizedDescription)")
            }
        }
    }

    func removeSkillFromSelectedProject(_ item: SkillListItem) {
        guard let selectedProject else {
            skillStatusMessage = "Select a project first."
            return
        }

        isSkillOperationInProgress = true
        skillStatusMessage = nil

        Task {
            defer { isSkillOperationInProgress = false }
            do {
                try await removeSkillInstallRecordAndLinks(
                    item,
                    uninstallSharedSkill: false,
                    limitToProjectID: selectedProject.id
                )
                try await refreshSkills()
                await refreshSkillsCatalog()
                if selectedSkillIDForComposer == item.id,
                   !skills.contains(where: { $0.id == item.id && $0.isEnabledForSelectedProject })
                {
                    selectedSkillIDForComposer = nil
                }
                skillStatusMessage = "Removed \(item.skill.name) from \(selectedProject.name)."
                appendLog(.info, "Removed skill \(item.skill.name) from project \(selectedProject.id.uuidString)")
            } catch {
                skillStatusMessage = "Failed to remove skill from project: \(error.localizedDescription)"
                appendLog(.error, "Skill remove-from-project failed for \(item.skill.name): \(error.localizedDescription)")
            }
        }
    }

    func revealSkill(_ item: SkillListItem) {
        let url = URL(fileURLWithPath: item.skill.skillPath, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func selectSkillForComposer(_ item: SkillListItem) {
        guard item.isEnabledForSelectedProject else {
            skillStatusMessage = "Install this skill for the selected project first."
            return
        }

        selectedSkillIDForComposer = item.id
        let trigger = "$\(item.skill.name)"
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(trigger) {
            composerText = trimmed.isEmpty ? trigger : "\(trimmed)\n\(trigger)"
        }
    }

    func clearSelectedSkillForComposer() {
        selectedSkillIDForComposer = nil
    }

    func applyComposerSkillAutocompleteSuggestion(_ item: SkillListItem) {
        guard item.isEnabledForSelectedProject else {
            skillStatusMessage = "Install this skill for the selected project before using it."
            return
        }

        let trigger = "$\(item.skill.name)"
        if let tokenMatch = composerSkillTokenMatch(in: composerText) {
            composerText.replaceSubrange(tokenMatch.range, with: "\(trigger) ")
        } else {
            let needsSeparator = !composerText.isEmpty && !composerText.hasSuffix(" ") && !composerText.hasSuffix("\n")
            composerText += needsSeparator ? " \(trigger) " : "\(trigger) "
        }

        selectedSkillIDForComposer = item.id
        skillStatusMessage = nil
    }

    func applyAllProjectsSkillLinksIfNeeded(to project: ProjectRecord) async throws {
        guard let skillInstallRegistryRepository else {
            return
        }

        let allProjectRecords = try await skillInstallRegistryRepository.list()
            .filter { $0.mode == .all }
        guard !allProjectRecords.isEmpty else {
            return
        }

        let linkManager = SkillLinkManager(sharedStoreRootURL: storagePaths.sharedSkillsStoreURL)
        let projectRootURL = URL(fileURLWithPath: project.path, isDirectory: true)
        for record in allProjectRecords {
            let sharedSkillURL = URL(fileURLWithPath: record.sharedPath, isDirectory: true)
            guard FileManager.default.fileExists(atPath: sharedSkillURL.path) else {
                continue
            }

            let folderName = sharedSkillURL.lastPathComponent
            _ = try linkManager.reconcileProjectSkillLink(
                folderName: folderName,
                sharedSkillDirectoryURL: sharedSkillURL,
                projectRootURL: projectRootURL
            )
        }
    }

    func migrateLegacySkillInstallsIfNeeded() async {
        guard let preferenceRepository,
              let skillInstallRegistryRepository
        else {
            return
        }

        do {
            if try await preferenceRepository.getPreference(key: .skillsInstallMigrationV1) == "1" {
                return
            }

            let existingInstallRecords = try await skillInstallRegistryRepository.list()
            if !existingInstallRecords.isEmpty {
                try await preferenceRepository.setPreference(key: .skillsInstallMigrationV1, value: "1")
                return
            }

            let allProjects: [ProjectRecord] = if let projectRepository {
                try await projectRepository.listProjects()
            } else {
                projects
            }

            let candidates = try await collectLegacySkillCandidates(projects: allProjects)
            if candidates.isEmpty {
                try await preferenceRepository.setPreference(key: .skillsInstallMigrationV1, value: "1")
                return
            }

            let enablementSnapshot = try await legacySkillEnablementSnapshot(projects: allProjects)
            let linkManager = SkillLinkManager(sharedStoreRootURL: storagePaths.sharedSkillsStoreURL)
            let fileManager = FileManager.default
            var migratedCount = 0

            for candidate in candidates {
                do {
                    let hasGlobalEnablement = enablementSnapshot.globalPaths.contains(candidate.resolvedPath)
                        || enablementSnapshot.generalPaths.contains(candidate.resolvedPath)
                    let shouldInstallForAllProjects = hasGlobalEnablement || candidate.discoveredGlobally

                    var selectedProjectIDs = candidate.projectIDs
                    for (projectID, enabledPaths) in enablementSnapshot.projectPathsByProjectID where
                        enabledPaths.contains(candidate.resolvedPath)
                    {
                        selectedProjectIDs.insert(projectID)
                    }

                    let targetProjects: [ProjectRecord] = if shouldInstallForAllProjects {
                        allProjects
                    } else {
                        allProjects.filter { selectedProjectIDs.contains($0.id) }
                    }

                    guard shouldInstallForAllProjects || !targetProjects.isEmpty else {
                        continue
                    }

                    let source = candidate.skill.installMetadata?.source
                        ?? candidate.skill.sourceURL
                        ?? "local:\(candidate.skill.name)"
                    let sharedSkillURL = try ensureLegacySkillIsInSharedStore(
                        candidate: candidate,
                        source: source,
                        projects: allProjects
                    )
                    let sharedSkillPath = sharedSkillURL.standardizedFileURL.path
                    guard CodexChatStoragePaths.isPath(
                        sharedSkillPath,
                        insideRoot: storagePaths.sharedSkillsStoreURL.path
                    ) else {
                        appendLog(.warning, "Skipping skill migration outside shared store root: \(sharedSkillPath)")
                        continue
                    }

                    let folderName = sharedSkillURL.lastPathComponent
                    for project in targetProjects {
                        let projectRootURL = URL(fileURLWithPath: project.path, isDirectory: true)
                        _ = try linkManager.reconcileProjectSkillLink(
                            folderName: folderName,
                            sharedSkillDirectoryURL: sharedSkillURL,
                            projectRootURL: projectRootURL
                        )
                    }

                    let mode: SkillInstallMode = shouldInstallForAllProjects ? .all : .selected
                    let projectIDs: [UUID] = mode == .all
                        ? []
                        : targetProjects.map(\.id).sorted { $0.uuidString < $1.uuidString }
                    let skillID = SkillStoreKeyBuilder.makeKey(source: source, fallbackName: folderName)
                    _ = try await skillInstallRegistryRepository.upsert(
                        SkillInstallRecord(
                            skillID: skillID,
                            source: source,
                            installer: mapSkillInstallMethod(candidate.skill.installMetadata?.installer ?? .git),
                            sharedPath: sharedSkillPath,
                            mode: mode,
                            projectIDs: projectIDs
                        )
                    )

                    if !fileManager.fileExists(atPath: sharedSkillPath) {
                        appendLog(.warning, "Shared skill path missing after migration: \(sharedSkillPath)")
                        continue
                    }
                    migratedCount += 1
                } catch {
                    appendLog(
                        .warning,
                        "Legacy skill migration skipped for \(candidate.skill.name): \(error.localizedDescription)"
                    )
                }
            }

            try await preferenceRepository.setPreference(key: .skillsInstallMigrationV1, value: "1")
            if migratedCount > 0 {
                appendLog(.info, "Migrated \(migratedCount) legacy skill install(s) into shared store.")
            }
        } catch {
            appendLog(.warning, "Legacy skill migration failed: \(error.localizedDescription)")
        }
    }

    private struct LegacySkillCandidate {
        var skill: DiscoveredSkill
        var resolvedPath: String
        var discoveredGlobally: Bool
        var projectIDs: Set<UUID>
    }

    private struct LegacySkillEnablementSnapshot {
        var globalPaths: Set<String>
        var generalPaths: Set<String>
        var projectPathsByProjectID: [UUID: Set<String>]
    }

    private func collectLegacySkillCandidates(projects: [ProjectRecord]) async throws -> [LegacySkillCandidate] {
        var byResolvedPath: [String: LegacySkillCandidate] = [:]

        func absorb(_ skills: [DiscoveredSkill], projectID: UUID?) {
            for skill in skills {
                let resolvedPath = resolvedSkillPath(skill.skillPath)
                var candidate = byResolvedPath[resolvedPath] ?? LegacySkillCandidate(
                    skill: skill,
                    resolvedPath: resolvedPath,
                    discoveredGlobally: false,
                    projectIDs: []
                )

                if candidate.skill.installMetadata == nil, skill.installMetadata != nil {
                    candidate.skill = skill
                }
                if candidate.skill.sourceURL == nil, skill.sourceURL != nil {
                    candidate.skill = skill
                }

                if skill.scope == .global {
                    candidate.discoveredGlobally = true
                }
                if skill.scope == .project, let projectID {
                    candidate.projectIDs.insert(projectID)
                }

                byResolvedPath[resolvedPath] = candidate
            }
        }

        let globalSkills = try skillCatalogService.discoverSkills(projectPath: nil)
        absorb(globalSkills, projectID: nil)
        for project in projects {
            let discovered = try skillCatalogService.discoverSkills(projectPath: project.path)
            absorb(discovered, projectID: project.id)
        }

        return byResolvedPath.values.sorted {
            if $0.skill.scope != $1.skill.scope {
                return $0.skill.scope.rawValue < $1.skill.scope.rawValue
            }
            return $0.skill.name.localizedCaseInsensitiveCompare($1.skill.name) == .orderedAscending
        }
    }

    private func legacySkillEnablementSnapshot(projects: [ProjectRecord]) async throws -> LegacySkillEnablementSnapshot {
        guard let projectSkillEnablementRepository else {
            return LegacySkillEnablementSnapshot(
                globalPaths: [],
                generalPaths: [],
                projectPathsByProjectID: [:]
            )
        }

        let rawGlobalPaths = try await projectSkillEnablementRepository.enabledSkillPaths(target: .global, projectID: nil)
        let globalPaths = resolveSkillPaths(rawGlobalPaths)
        let rawGeneralPaths = try await projectSkillEnablementRepository.enabledSkillPaths(target: .general, projectID: nil)
        let generalPaths = resolveSkillPaths(rawGeneralPaths)

        var projectPathsByProjectID: [UUID: Set<String>] = [:]
        for project in projects {
            let enabledPaths = try await projectSkillEnablementRepository.enabledSkillPaths(projectID: project.id)
            projectPathsByProjectID[project.id] = resolveSkillPaths(enabledPaths)
        }

        return LegacySkillEnablementSnapshot(
            globalPaths: globalPaths,
            generalPaths: generalPaths,
            projectPathsByProjectID: projectPathsByProjectID
        )
    }

    private func ensureLegacySkillIsInSharedStore(
        candidate: LegacySkillCandidate,
        source: String,
        projects: [ProjectRecord]
    ) throws -> URL {
        let fileManager = FileManager.default
        let sharedStoreRootURL = storagePaths.sharedSkillsStoreURL.standardizedFileURL
        try fileManager.createDirectory(at: sharedStoreRootURL, withIntermediateDirectories: true)

        let legacySkillURL = URL(fileURLWithPath: candidate.resolvedPath, isDirectory: true).standardizedFileURL
        if CodexChatStoragePaths.isPath(legacySkillURL.path, insideRoot: sharedStoreRootURL.path) {
            return legacySkillURL
        }

        guard fileManager.fileExists(atPath: legacySkillURL.path) else {
            throw NSError(
                domain: "CodexChatApp.SkillInstallMigration",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Legacy skill path does not exist: \(legacySkillURL.path)"]
            )
        }

        let allowedRoots = legacyManagedSkillRoots(projects: projects)
        guard allowedRoots.contains(where: { CodexChatStoragePaths.isPath(legacySkillURL.path, insideRoot: $0) }) else {
            throw NSError(
                domain: "CodexChatApp.SkillInstallMigration",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Legacy skill path is outside managed roots."]
            )
        }

        let baseFolderName = SkillStoreKeyBuilder.makeKey(
            source: source,
            fallbackName: legacySkillURL.lastPathComponent
        )
        var destinationURL = sharedStoreRootURL.appendingPathComponent(baseFolderName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: destinationURL.path) {
            let destinationPath = resolvedSkillPath(destinationURL.path)
            if destinationPath == legacySkillURL.path {
                return destinationURL
            }
            destinationURL = sharedStoreRootURL.appendingPathComponent("\(baseFolderName)-\(suffix)", isDirectory: true)
            suffix += 1
        }

        try fileManager.moveItem(at: legacySkillURL, to: destinationURL)
        return destinationURL
    }

    private func legacyManagedSkillRoots(projects: [ProjectRecord]) -> [String] {
        var roots = [
            storagePaths.sharedSkillsStoreURL.path,
            storagePaths.codexHomeURL.appendingPathComponent("skills", isDirectory: true).path,
            storagePaths.agentsHomeURL.appendingPathComponent("skills", isDirectory: true).path,
        ]

        for project in projects {
            let projectRootURL = URL(fileURLWithPath: project.path, isDirectory: true)
            roots.append(projectRootURL.appendingPathComponent(".agents/skills", isDirectory: true).path)
            roots.append(projectRootURL.appendingPathComponent(".codex/skills", isDirectory: true).path)
        }

        var unique: [String] = []
        var seen: Set<String> = []
        for root in roots {
            let normalized = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.path
            if seen.insert(normalized).inserted {
                unique.append(normalized)
            }
        }
        return unique
    }

    private func resolvedSkillPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private func resolveSkillPaths(_ paths: Set<String>) -> Set<String> {
        Set(paths.map { resolvedSkillPath($0) })
    }

    private func registerInstalledSkill(
        source: String,
        installer: SkillInstallerKind,
        requestedScope: SkillInstallScope,
        selectedProjectIDsOverride: [UUID]?,
        installedPath: String
    ) async throws {
        let sharedSkillURL = URL(fileURLWithPath: installedPath, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let sharedPath = sharedSkillURL.path
        let folderName = sharedSkillURL.lastPathComponent
        let skillID = SkillStoreKeyBuilder.makeKey(source: source, fallbackName: folderName)

        let targetProjects: [ProjectRecord]
        let mode: SkillInstallMode
        let selectedProjectIDs: [UUID]
        switch requestedScope {
        case .global:
            mode = .all
            selectedProjectIDs = []
            targetProjects = try await projectRepository?.listProjects() ?? []
        case .project:
            let requestedProjectIDs: Set<UUID> = if let selectedProjectIDsOverride {
                Set(selectedProjectIDsOverride)
            } else if let selectedProject {
                [selectedProject.id]
            } else {
                []
            }
            guard !requestedProjectIDs.isEmpty else {
                throw NSError(
                    domain: "CodexChatApp.SkillInstall",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Select a project before installing to selected projects."]
                )
            }

            let knownProjects = try await projectRepository?.listProjects() ?? projects
            let resolvedProjects = knownProjects.filter { requestedProjectIDs.contains($0.id) }
            guard !resolvedProjects.isEmpty else {
                throw NSError(
                    domain: "CodexChatApp.SkillInstall",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No valid target projects were found for skill install."]
                )
            }
            mode = .selected
            selectedProjectIDs = resolvedProjects.map(\.id)
            targetProjects = resolvedProjects
        }

        let linkManager = SkillLinkManager(sharedStoreRootURL: storagePaths.sharedSkillsStoreURL)
        for project in targetProjects {
            _ = try linkManager.ensureProjectSkillLink(
                folderName: folderName,
                sharedSkillDirectoryURL: sharedSkillURL,
                projectRootURL: URL(fileURLWithPath: project.path, isDirectory: true)
            )
        }

        if let skillInstallRegistryRepository {
            _ = try await skillInstallRegistryRepository.upsert(
                SkillInstallRecord(
                    skillID: skillID,
                    source: source,
                    installer: mapSkillInstallMethod(installer),
                    sharedPath: sharedPath,
                    mode: mode,
                    projectIDs: selectedProjectIDs
                )
            )
        }
    }

    private func mapSkillInstallMethod(_ installer: SkillInstallerKind) -> SkillInstallMethod {
        switch installer {
        case .git:
            .git
        case .npx:
            .npx
        }
    }

    private func removeSkillInstallRecordAndLinks(
        _ item: SkillListItem,
        uninstallSharedSkill: Bool,
        limitToProjectID: UUID? = nil
    ) async throws {
        guard let skillInstallRegistryRepository else {
            throw NSError(
                domain: "CodexChatApp.SkillInstall",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Skill install registry is unavailable."]
            )
        }

        guard var record = try await installRecord(for: item) else {
            throw NSError(
                domain: "CodexChatApp.SkillInstall",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Skill install record was not found."]
            )
        }

        let sharedSkillURL = URL(fileURLWithPath: record.sharedPath, isDirectory: true)
        let folderName = sharedSkillURL.lastPathComponent
        let allProjects = try await projectRepository?.listProjects() ?? projects
        let linkManager = SkillLinkManager(sharedStoreRootURL: storagePaths.sharedSkillsStoreURL)

        if let limitToProjectID {
            let project = allProjects.first(where: { $0.id == limitToProjectID })
            if let project {
                try linkManager.removeProjectSkillLink(
                    folderName: folderName,
                    projectRootURL: URL(fileURLWithPath: project.path, isDirectory: true)
                )
            }

            switch record.mode {
            case .all:
                let remainingProjectIDs = allProjects
                    .map(\.id)
                    .filter { $0 != limitToProjectID }
                if remainingProjectIDs.isEmpty {
                    try await skillInstallRegistryRepository.delete(skillID: record.skillID)
                    if uninstallSharedSkill, FileManager.default.fileExists(atPath: sharedSkillURL.path) {
                        try FileManager.default.removeItem(at: sharedSkillURL)
                    }
                    return
                }
                record = SkillInstallRecord(
                    skillID: record.skillID,
                    source: record.source,
                    installer: record.installer,
                    sharedPath: record.sharedPath,
                    mode: .selected,
                    projectIDs: remainingProjectIDs,
                    createdAt: record.createdAt,
                    updatedAt: Date()
                )
                _ = try await skillInstallRegistryRepository.upsert(record)
            case .selected:
                let remainingProjectIDs = record.projectIDs.filter { $0 != limitToProjectID }
                if remainingProjectIDs.isEmpty {
                    try await skillInstallRegistryRepository.delete(skillID: record.skillID)
                    if uninstallSharedSkill, FileManager.default.fileExists(atPath: sharedSkillURL.path) {
                        try FileManager.default.removeItem(at: sharedSkillURL)
                    }
                    return
                }
                record = SkillInstallRecord(
                    skillID: record.skillID,
                    source: record.source,
                    installer: record.installer,
                    sharedPath: record.sharedPath,
                    mode: .selected,
                    projectIDs: remainingProjectIDs,
                    createdAt: record.createdAt,
                    updatedAt: Date()
                )
                _ = try await skillInstallRegistryRepository.upsert(record)
            }
            return
        }

        let targetProjects: [ProjectRecord] = switch record.mode {
        case .all:
            allProjects
        case .selected:
            allProjects.filter { record.projectIDs.contains($0.id) }
        }

        for project in targetProjects {
            try linkManager.removeProjectSkillLink(
                folderName: folderName,
                projectRootURL: URL(fileURLWithPath: project.path, isDirectory: true)
            )
        }

        try await skillInstallRegistryRepository.delete(skillID: record.skillID)
        if uninstallSharedSkill, FileManager.default.fileExists(atPath: sharedSkillURL.path) {
            try FileManager.default.removeItem(at: sharedSkillURL)
        }
    }

    private func installRecord(for item: SkillListItem) async throws -> SkillInstallRecord? {
        guard let skillInstallRegistryRepository else {
            return nil
        }
        let resolvedSkillPath = URL(fileURLWithPath: item.skill.skillPath, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let records = try await skillInstallRegistryRepository.list()
        return records.first { record in
            URL(fileURLWithPath: record.sharedPath, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path == resolvedSkillPath
        }
    }

    func blockedCapabilitiesForSkillInstall(
        source: String,
        scope: SkillInstallScope,
        installer: SkillInstallerKind
    ) -> Set<ExtensibilityCapability> {
        guard scope == .project else {
            return []
        }

        return blockedExtensibilityCapabilities(
            for: requiredExtensibilityCapabilitiesForSkillInstall(
                source: source,
                installer: installer
            ),
            projectID: selectedProjectID
        )
    }

    func requiredExtensibilityCapabilitiesForSkillInstall(
        source: String,
        installer: SkillInstallerKind
    ) -> Set<ExtensibilityCapability> {
        switch installer {
        case .npx:
            [.network, .runtimeControl]
        case .git:
            skillInstallLikelyRequiresNetwork(source) ? [.network] : []
        }
    }

    func skillInstallLikelyRequiresNetwork(_ source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
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

    private func composerSkillTokenMatch(in text: String) -> ComposerSkillTokenMatch? {
        guard !text.isEmpty else {
            return nil
        }

        let tokenStart = text.lastIndex(where: \.isWhitespace).map { text.index(after: $0) } ?? text.startIndex
        guard tokenStart < text.endIndex, text[tokenStart] == "$" else {
            return nil
        }

        let queryStart = text.index(after: tokenStart)
        let query = String(text[queryStart ..< text.endIndex])
        guard query.allSatisfy(\.isComposerSkillTokenCharacter) else {
            return nil
        }

        return ComposerSkillTokenMatch(range: tokenStart ..< text.endIndex, query: query)
    }

    private func sortedComposerSkillSuggestions(_ items: [SkillListItem]) -> [SkillListItem] {
        items.sorted { lhs, rhs in
            if lhs.isEnabledForSelectedProject != rhs.isEnabledForSelectedProject {
                return lhs.isEnabledForSelectedProject
            }
            return lhs.skill.name.localizedCaseInsensitiveCompare(rhs.skill.name) == .orderedAscending
        }
    }

    private func composerSkill(_ item: SkillListItem, matches query: String) -> Bool {
        item.skill.name.localizedStandardContains(query)
            || item.skill.description.localizedStandardContains(query)
            || item.skill.scope.rawValue.localizedStandardContains(query)
            || item.skill.name
            .replacingOccurrences(of: " ", with: "-")
            .localizedStandardContains(query)
    }
}

private struct ComposerSkillTokenMatch {
    let range: Range<String.Index>
    let query: String
}

private extension Character {
    var isComposerSkillTokenCharacter: Bool {
        isLetter || isNumber || self == "-" || self == "_"
    }
}
