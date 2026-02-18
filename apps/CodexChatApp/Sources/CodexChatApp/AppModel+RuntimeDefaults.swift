import CodexChatCore
import CodexKit
import Foundation

extension AppModel {
    struct GlobalSafetyApplySummary {
        let updated: Int
        let skipped: Int
        let failed: Int

        var message: String {
            "Applied global safety defaults: updated \(updated), skipped \(skipped), failed \(failed)."
        }
    }

    var modelPresets: [String] {
        ["gpt-5-codex", "gpt-5", "o4-mini"]
    }

    func setDefaultModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        guard trimmed != defaultModel else {
            return
        }

        defaultModel = trimmed
        updateCodexConfigValue(path: [.key("model")], value: .string(trimmed))

        Task {
            await saveCodexConfig(restartRuntime: false)
        }
    }

    func setDefaultReasoning(_ reasoning: ReasoningLevel) {
        guard reasoning != defaultReasoning else {
            return
        }

        defaultReasoning = reasoning
        updateCodexConfigValue(path: [.key("model_reasoning_effort")], value: .string(reasoning.rawValue))

        Task {
            await saveCodexConfig(restartRuntime: false)
        }
    }

    func setDefaultWebSearch(_ webSearch: ProjectWebSearchMode) {
        guard webSearch != defaultWebSearch else {
            return
        }

        defaultWebSearch = webSearch
        updateCodexConfigValue(path: [.key("web_search")], value: .string(webSearch.rawValue))

        Task {
            await saveCodexConfig(restartRuntime: false)
        }
    }

    func saveGlobalSafetyDefaults(_ settings: ProjectSafetySettings, applyToExistingProjects: Bool) {
        defaultSafetySettings = settings

        updateCodexConfigValue(path: [.key("sandbox_mode")], value: .string(mapSandboxModeString(settings.sandboxMode)))
        updateCodexConfigValue(path: [.key("approval_policy")], value: .string(mapApprovalPolicyString(settings.approvalPolicy)))
        updateCodexConfigValue(path: [.key("web_search")], value: .string(settings.webSearch.rawValue))
        updateCodexConfigValue(
            path: [.key("sandbox_workspace_write"), .key("network_access")],
            value: .boolean(settings.networkAccess)
        )

        Task {
            do {
                await saveCodexConfig(restartRuntime: false)

                if applyToExistingProjects {
                    let summary = try await applyGlobalSafetyDefaultsToExistingProjects()
                    runtimeDefaultsStatusMessage = summary.message
                } else {
                    runtimeDefaultsStatusMessage = "Saved global safety defaults. They apply to newly created projects."
                }
            } catch {
                runtimeDefaultsStatusMessage = "Failed to save global safety defaults: \(error.localizedDescription)"
                appendLog(.error, "Failed to save global safety defaults: \(error.localizedDescription)")
            }
        }
    }

    func applyGlobalSafetyDefaultsToProjectIfNeeded(projectID: UUID) async throws {
        guard let projectRepository,
              let project = try await projectRepository.getProject(id: projectID)
        else {
            return
        }

        guard project.sandboxMode != defaultSafetySettings.sandboxMode
            || project.approvalPolicy != defaultSafetySettings.approvalPolicy
            || project.networkAccess != defaultSafetySettings.networkAccess
            || project.webSearch != defaultSafetySettings.webSearch
        else {
            return
        }

        _ = try await projectRepository.updateProjectSafetySettings(id: projectID, settings: defaultSafetySettings)
    }

    func applyGlobalSafetyDefaultsToExistingProjects() async throws -> GlobalSafetyApplySummary {
        guard let projectRepository else {
            return GlobalSafetyApplySummary(updated: 0, skipped: 0, failed: 0)
        }

        let allProjects = try await projectRepository.listProjects()
        var updated = 0
        var skipped = 0
        var failed = 0

        for project in allProjects {
            let matchesDefaults = project.sandboxMode == defaultSafetySettings.sandboxMode
                && project.approvalPolicy == defaultSafetySettings.approvalPolicy
                && project.networkAccess == defaultSafetySettings.networkAccess
                && project.webSearch == defaultSafetySettings.webSearch

            if matchesDefaults {
                skipped += 1
                continue
            }

            do {
                _ = try await projectRepository.updateProjectSafetySettings(
                    id: project.id,
                    settings: defaultSafetySettings
                )
                updated += 1
            } catch {
                failed += 1
                appendLog(
                    .warning,
                    "Failed applying global safety defaults to project \(project.name): \(error.localizedDescription)"
                )
            }
        }

        if updated > 0 {
            try await refreshProjects()
        }

        return GlobalSafetyApplySummary(updated: updated, skipped: skipped, failed: failed)
    }

    func runtimeTurnOptions() -> RuntimeTurnOptions {
        let model = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveModel = model.isEmpty ? nil : model

        return RuntimeTurnOptions(
            model: effectiveModel,
            reasoningEffort: defaultReasoning.rawValue,
            experimental: [:]
        )
    }

    func effectiveWebSearchMode(
        preferred: ProjectWebSearchMode,
        projectPolicy: ProjectWebSearchMode
    ) -> ProjectWebSearchMode {
        let preferredRank = webSearchRank(preferred)
        let policyRank = webSearchRank(projectPolicy)
        return preferredRank <= policyRank ? preferred : projectPolicy
    }

    func effectiveWebSearchModeForSelectedProject() -> ProjectWebSearchMode {
        guard let project = selectedProject else {
            return defaultWebSearch
        }
        return effectiveWebSearchMode(preferred: defaultWebSearch, projectPolicy: project.webSearch)
    }

    func isDefaultWebSearchClampedForSelectedProject() -> Bool {
        guard let project = selectedProject else {
            return false
        }
        return effectiveWebSearchMode(preferred: defaultWebSearch, projectPolicy: project.webSearch) != defaultWebSearch
    }

    private func webSearchRank(_ mode: ProjectWebSearchMode) -> Int {
        switch mode {
        case .disabled:
            0
        case .cached:
            1
        case .live:
            2
        }
    }
}
