import CodexChatCore
import CodexSkills
import Foundation

extension AppModel {
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
        installer: SkillInstallerKind
    ) {
        if scope == .project, selectedProject == nil {
            skillStatusMessage = "Select a project to install a project-scoped skill."
            return
        }

        isSkillOperationInProgress = true
        skillStatusMessage = nil

        let request = SkillInstallRequest(
            source: source,
            scope: mapSkillScope(scope),
            projectPath: selectedProject?.path,
            installer: installer
        )

        Task {
            defer { isSkillOperationInProgress = false }
            do {
                let result = try skillCatalogService.installSkill(request)
                try await refreshSkills()
                await refreshSkillsCatalog()
                skillStatusMessage = "Installed skill to \(result.installedPath)."
                appendLog(.info, "Installed skill from \(source)")
            } catch {
                skillStatusMessage = "Skill install failed: \(error.localizedDescription)"
                appendLog(.error, "Skill install failed: \(error.localizedDescription)")
            }
        }
    }

    func installCatalogSkill(_ listing: CatalogSkillListing, scope: SkillInstallScope) {
        let source = listing.installSource ?? listing.repositoryURL
        guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            skillStatusMessage = "Catalog listing \(listing.name) has no install source URL."
            return
        }

        installSkill(source: source, scope: scope, installer: .git)
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
                skillStatusMessage = "Skill update failed: \(error.localizedDescription)"
                appendLog(.error, "Skill update failed: \(error.localizedDescription)")
            }
        }
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

        let target = selectedSkillEnablementTarget(for: item)
        let targetProjectID: UUID?
        switch target {
        case .global, .general:
            targetProjectID = nil
        case .project:
            guard let selectedProjectID else {
                skillStatusMessage = "Select a project before enabling project-target skills."
                return
            }
            targetProjectID = selectedProjectID
        }

        Task {
            do {
                try await projectSkillEnablementRepository.setSkillEnabled(
                    target: target,
                    projectID: targetProjectID,
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

    private func mapSkillScope(_ scope: SkillInstallScope) -> SkillScope {
        switch scope {
        case .project:
            .project
        case .global:
            .global
        }
    }
}
