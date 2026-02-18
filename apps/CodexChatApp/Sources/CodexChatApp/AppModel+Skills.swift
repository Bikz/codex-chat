import CodexChatCore
import CodexSkills
import Foundation

extension AppModel {
    func refreshSkillsSurface() {
        Task {
            do {
                try await refreshSkills()
            } catch {
                skillsState = .failed(error.localizedDescription)
                skillStatusMessage = "Failed to refresh skills: \(error.localizedDescription)"
                appendLog(.error, "Refresh skills failed: \(error.localizedDescription)")
            }
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
                skillStatusMessage = "Installed skill to \(result.installedPath)."
                appendLog(.info, "Installed skill from \(source)")
            } catch {
                skillStatusMessage = "Skill install failed: \(error.localizedDescription)"
                appendLog(.error, "Skill install failed: \(error.localizedDescription)")
            }
        }
    }

    func updateSkill(_ item: SkillListItem) {
        isSkillOperationInProgress = true
        skillStatusMessage = nil

        Task {
            defer { isSkillOperationInProgress = false }
            do {
                _ = try skillCatalogService.updateSkill(at: item.skill.skillPath)
                try await refreshSkills()
                skillStatusMessage = "Updated \(item.skill.name)."
                appendLog(.info, "Updated skill \(item.skill.name)")
            } catch {
                skillStatusMessage = "Skill update failed: \(error.localizedDescription)"
                appendLog(.error, "Skill update failed: \(error.localizedDescription)")
            }
        }
    }

    func setSkillEnabled(_ item: SkillListItem, enabled: Bool) {
        guard let selectedProjectID,
              let projectSkillEnablementRepository
        else {
            skillStatusMessage = "Select a project before enabling skills."
            return
        }

        Task {
            do {
                try await projectSkillEnablementRepository.setSkillEnabled(
                    projectID: selectedProjectID,
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
        guard item.isEnabledForProject else {
            skillStatusMessage = "Enable the skill for this project first."
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
