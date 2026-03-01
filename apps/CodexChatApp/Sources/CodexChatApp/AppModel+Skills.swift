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

        let sortedSkills = sortedComposerSkillSuggestions(skills)
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
            skillStatusMessage = "Select a project to install a project-scoped skill."
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

    func setSkillEnablementTarget(_ target: SkillEnablementTarget, for skillID: String) {
        if target == .project, selectedProjectID == nil {
            skillStatusMessage = "Select a project to enable project-target skills."
            return
        }
        skillEnablementTargetSelectionBySkillID[skillID] = target
    }

    func selectedSkillEnablementTarget(for item: SkillListItem) -> SkillEnablementTarget {
        if let selected = skillEnablementTargetSelectionBySkillID[item.id] {
            if selected == .project, selectedProjectID == nil {
                return .global
            }
            return selected
        }
        return selectedProjectID == nil ? .global : .project
    }

    func setSkillEnabled(_ item: SkillListItem, enabled: Bool) {
        guard let projectSkillEnablementRepository else {
            skillStatusMessage = "Skill enablement repository unavailable."
            return
        }

        guard let request = skillEnablementRequest(for: item) else {
            return
        }

        Task {
            do {
                try await projectSkillEnablementRepository.setSkillEnabled(
                    target: request.target,
                    projectID: request.projectID,
                    skillPath: item.skill.skillPath,
                    enabled: enabled
                )
                try await refreshSkills()
                if !enabled, selectedSkillIDForComposer == item.id {
                    selectedSkillIDForComposer = nil
                }
            } catch {
                skillStatusMessage = "Failed to update skill enablement: \(error.localizedDescription)"
                appendLog(.error, "Skill enablement update failed: \(error.localizedDescription)")
            }
        }
    }

    func selectSkillForComposer(_ item: SkillListItem) {
        guard item.isEnabledForSelectedProject else {
            skillStatusMessage = "Enable the skill for this context first."
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
        let trigger = "$\(item.skill.name)"
        if let tokenMatch = composerSkillTokenMatch(in: composerText) {
            composerText.replaceSubrange(tokenMatch.range, with: "\(trigger) ")
        } else {
            let needsSeparator = !composerText.isEmpty && !composerText.hasSuffix(" ") && !composerText.hasSuffix("\n")
            composerText += needsSeparator ? " \(trigger) " : "\(trigger) "
        }

        var enablementRequest: SkillEnablementRequest?
        if !item.isEnabledForSelectedProject {
            guard let request = skillEnablementRequest(for: item) else {
                selectedSkillIDForComposer = nil
                return
            }
            enablementRequest = request
            optimisticallyEnableSkillForSelectedContext(skillID: item.id, target: request.target)
        }

        selectedSkillIDForComposer = item.id
        skillStatusMessage = nil

        guard let enablementRequest,
              let projectSkillEnablementRepository
        else {
            return
        }

        Task {
            do {
                try await projectSkillEnablementRepository.setSkillEnabled(
                    target: enablementRequest.target,
                    projectID: enablementRequest.projectID,
                    skillPath: item.skill.skillPath,
                    enabled: true
                )
                try await refreshSkills()
            } catch {
                skillStatusMessage = "Failed to auto-enable skill \(item.skill.name): \(error.localizedDescription)"
                appendLog(.error, "Skill auto-enable failed for \(item.skill.name): \(error.localizedDescription)")
            }
        }
    }

    private func optimisticallyEnableSkillForSelectedContext(skillID: String, target: SkillEnablementTarget) {
        guard case var .loaded(items) = skillsState,
              let index = items.firstIndex(where: { $0.id == skillID })
        else {
            return
        }

        items[index].enabledTargets.insert(target)
        items[index].isEnabledForSelectedProject = true
        skillsState = .loaded(items)
    }

    private struct SkillEnablementRequest {
        let target: SkillEnablementTarget
        let projectID: UUID?
    }

    private func skillEnablementRequest(for item: SkillListItem) -> SkillEnablementRequest? {
        let target = selectedSkillEnablementTarget(for: item)
        switch target {
        case .global, .general:
            return SkillEnablementRequest(target: target, projectID: nil)
        case .project:
            guard let selectedProjectID else {
                skillStatusMessage = "Select a project before enabling project-target skills."
                return nil
            }
            return SkillEnablementRequest(target: .project, projectID: selectedProjectID)
        }
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
