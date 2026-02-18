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

    func loadRuntimeDefaultsFromPreferences() async throws {
        guard let preferenceRepository else {
            return
        }

        if let rawModel = try await preferenceRepository.getPreference(key: .runtimeDefaultModel),
           !rawModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            defaultModel = rawModel
        }

        if let rawReasoning = try await preferenceRepository.getPreference(key: .runtimeDefaultReasoning),
           let reasoning = ReasoningLevel(rawValue: rawReasoning)
        {
            defaultReasoning = reasoning
        }

        if let rawWebSearch = try await preferenceRepository.getPreference(key: .runtimeDefaultWebSearch),
           let webSearch = ProjectWebSearchMode(rawValue: rawWebSearch)
        {
            defaultWebSearch = webSearch
        }

        if let rawSafety = try await preferenceRepository.getPreference(key: .runtimeDefaultSafety),
           let data = rawSafety.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ProjectSafetySettings.self, from: data)
        {
            defaultSafetySettings = decoded
        }

        if let rawFlags = try await preferenceRepository.getPreference(key: .runtimeExperimentalFlags),
           let data = rawFlags.data(using: .utf8),
           let rawValues = try? JSONDecoder().decode([String].self, from: data)
        {
            let mapped = Set(rawValues.compactMap(ExperimentalFlag.init(rawValue:)))
            experimentalFlags = mapped
        }
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
        Task {
            try? await persistRuntimePreference(key: .runtimeDefaultModel, value: trimmed)
        }
    }

    func setDefaultReasoning(_ reasoning: ReasoningLevel) {
        guard reasoning != defaultReasoning else {
            return
        }

        defaultReasoning = reasoning
        Task {
            try? await persistRuntimePreference(key: .runtimeDefaultReasoning, value: reasoning.rawValue)
        }
    }

    func setDefaultWebSearch(_ webSearch: ProjectWebSearchMode) {
        guard webSearch != defaultWebSearch else {
            return
        }

        defaultWebSearch = webSearch
        Task {
            try? await persistRuntimePreference(key: .runtimeDefaultWebSearch, value: webSearch.rawValue)
        }
    }

    func setExperimentalFlag(_ flag: ExperimentalFlag, enabled: Bool) {
        var updated = experimentalFlags
        if enabled {
            updated.insert(flag)
        } else {
            updated.remove(flag)
        }

        guard updated != experimentalFlags else {
            return
        }

        experimentalFlags = updated
        Task {
            try? await persistRuntimePreference(
                key: .runtimeExperimentalFlags,
                value: encodedExperimentalFlags(updated)
            )
        }
    }

    func saveGlobalSafetyDefaults(_ settings: ProjectSafetySettings, applyToExistingProjects: Bool) {
        defaultSafetySettings = settings

        Task {
            do {
                let encoded = try encodedSafetySettings(settings)
                try await persistRuntimePreference(key: .runtimeDefaultSafety, value: encoded)

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
        let experimental = Dictionary(uniqueKeysWithValues: experimentalFlags.map { ($0.rawValue, true) })

        return RuntimeTurnOptions(
            model: effectiveModel,
            reasoningEffort: defaultReasoning.rawValue,
            experimental: experimental
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

    private func persistRuntimePreference(key: AppPreferenceKey, value: String) async throws {
        guard let preferenceRepository else {
            return
        }
        try await preferenceRepository.setPreference(key: key, value: value)
    }

    private func encodedSafetySettings(_ settings: ProjectSafetySettings) throws -> String {
        let data = try JSONEncoder().encode(settings)
        return String(decoding: data, as: UTF8.self)
    }

    private func encodedExperimentalFlags(_ flags: Set<ExperimentalFlag>) -> String {
        let rawValues = flags.map(\.rawValue).sorted()
        guard let data = try? JSONEncoder().encode(rawValues) else {
            return "[]"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
