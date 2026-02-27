import CodexChatCore
import CodexKit
import Foundation

extension AppModel {
    private static let featuredModelIDs: [String] = [
        "gpt-5.3-codex",
        "gpt-5.3-codex-spark",
        "gpt-5.2-codex",
        "gpt-4o",
    ]

    struct GlobalSafetyApplySummary {
        let updated: Int
        let skipped: Int
        let failed: Int

        var message: String {
            "Applied global safety defaults: updated \(updated), skipped \(skipped), failed \(failed)."
        }
    }

    var modelPresets: [String] {
        let runtimeModelIDs = runtimeModelCatalog.map(\.id)
        if !runtimeModelIDs.isEmpty {
            return normalizeModelPresetIDs(runtimeModelIDs)
        }

        if let configuredModel = configuredModelOverride() {
            return normalizeModelPresetIDs([configuredModel])
        }

        let fallbackModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackModel.isEmpty {
            return normalizeModelPresetIDs([fallbackModel])
        }

        return normalizeModelPresetIDs([])
    }

    var featuredModelPresets: [String] {
        let presets = modelPresets
        guard !presets.isEmpty else {
            return []
        }

        var featured: [String] = []
        var seen: Set<String> = []

        for featuredID in Self.featuredModelIDs {
            guard let match = matchingModelPreset(featuredID, in: presets) else {
                continue
            }

            let normalizedMatch = match.lowercased()
            guard seen.insert(normalizedMatch).inserted else {
                continue
            }
            featured.append(match)
        }

        return featured
    }

    var overflowModelPresets: [String] {
        let featured = Set(featuredModelPresets.map { $0.lowercased() })
        return modelPresets.filter { !featured.contains($0.lowercased()) }
    }

    var runtimeDefaultModelID: String? {
        if let defaultModel = runtimeModelCatalog.first(where: \.isDefault) {
            return defaultModel.id
        }
        return runtimeModelCatalog.first?.id
    }

    var isUsingRuntimeDefaultModel: Bool {
        configuredModelOverride() == nil
    }

    var defaultModelDisplayName: String {
        let effectiveModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !effectiveModel.isEmpty else {
            return "Runtime default"
        }
        return modelDisplayName(for: effectiveModel)
    }

    var reasoningPresets: [ReasoningLevel] {
        let selectedModelID = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let supportedBySelectedModel = supportedReasoningLevels(forModelID: selectedModelID)
        if !supportedBySelectedModel.isEmpty {
            return supportedBySelectedModel
        }

        let inferred = inferredReasoningLevels(forModelID: selectedModelID)
        if !inferred.isEmpty {
            return inferred
        }

        let schemaReasoning = reasoningLevelsFromSchema()
        if !schemaReasoning.isEmpty {
            return schemaReasoning
        }

        return ReasoningLevel.allCases.sorted { reasoningRank($0) < reasoningRank($1) }
    }

    var webSearchPresets: [ProjectWebSearchMode] {
        let selectedModelID = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let supportedBySelectedModel = supportedWebSearchModes(forModelID: selectedModelID)
        if !supportedBySelectedModel.isEmpty {
            return supportedBySelectedModel
        }

        return ProjectWebSearchMode.allCases.sorted { webSearchRank($0) < webSearchRank($1) }
    }

    var canChooseReasoningForSelectedModel: Bool {
        reasoningPresets.count > 1
    }

    var canChooseWebSearchForSelectedModel: Bool {
        webSearchPresets.count > 1
    }

    func modelDisplayName(for modelID: String) -> String {
        let trimmedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            return "Runtime default"
        }

        if let model = runtimeModelInfo(for: trimmedID) {
            let displayName = model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = displayName.isEmpty ? trimmedID : displayName
            return canonicalModelLabel(resolvedName)
        }

        return canonicalModelLabel(trimmedID)
    }

    func modelMenuLabel(for modelID: String) -> String {
        let trimmedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            return "Runtime default"
        }

        if isAPIKeyOnlyModel(trimmedID) {
            let displayName = modelDisplayName(for: trimmedID)
            return "\(displayName) (api key only)"
        }

        return modelDisplayName(for: trimmedID)
    }

    func setDefaultModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredModel = configuredModelOverride()

        if trimmed.isEmpty {
            persistPreferredRuntimeModelPreference("")
            guard configuredModel != nil else {
                return
            }

            updateCodexConfigValue(path: [.key("model")], value: nil)
            Task {
                await saveCodexConfig(restartRuntime: false)
            }
            return
        }

        guard trimmed != configuredModel else {
            persistPreferredRuntimeModelPreference(trimmed)
            return
        }

        if isAPIKeyOnlyModel(trimmed), isSignedInWithChatGPTAuth() {
            accountStatusMessage = "\(trimmed) requires API key login. Enter an OpenAI API key to continue."
            presentAPIKeyPrompt()
            return
        }

        updateCodexConfigValue(path: [.key("model")], value: .string(trimmed))
        persistPreferredRuntimeModelPreference(trimmed)

        Task {
            await saveCodexConfig(restartRuntime: false)
        }
    }

    func setDefaultReasoning(_ reasoning: ReasoningLevel) {
        let clamped = clampedReasoningLevel(reasoning, forModelID: defaultModel)
        guard clamped != defaultReasoning else {
            return
        }

        defaultReasoning = clamped
        updateCodexConfigValue(path: [.key("model_reasoning_effort")], value: .string(clamped.rawValue))

        Task {
            await saveCodexConfig(restartRuntime: false)
        }
    }

    func setDefaultWebSearch(_ webSearch: ProjectWebSearchMode) {
        let clamped = clampedWebSearchMode(webSearch, forModelID: defaultModel)
        guard clamped != defaultWebSearch else {
            return
        }

        defaultWebSearch = clamped
        updateCodexConfigValue(path: [.key("web_search")], value: .string(clamped.rawValue))

        Task {
            await saveCodexConfig(restartRuntime: false)
        }
    }

    func mapReasoningLevel(_ value: String) -> ReasoningLevel {
        reasoningLevelIfKnown(value) ?? .medium
    }

    func reasoningLevelIfKnown(_ value: String) -> ReasoningLevel? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "none":
            return ReasoningLevel.none
        case "minimal":
            return ReasoningLevel.minimal
        case "low":
            return ReasoningLevel.low
        case "medium":
            return ReasoningLevel.medium
        case "high":
            return ReasoningLevel.high
        case "xhigh", "x-high", "extra-high", "extra_high":
            return ReasoningLevel.xhigh
        default:
            return nil
        }
    }

    func defaultReasoningForModel(_ modelID: String?) -> ReasoningLevel? {
        guard let model = runtimeModelInfo(for: modelID) else {
            return inferredReasoningLevels(forModelID: modelID).first
        }

        if let defaultReasoningEffort = model.defaultReasoningEffort,
           let mapped = reasoningLevelIfKnown(defaultReasoningEffort)
        {
            return mapped
        }

        let supported = supportedReasoningLevels(forModelID: model.id)
        return supported.first
    }

    func supportedReasoningLevels(forModelID modelID: String?) -> [ReasoningLevel] {
        guard let model = runtimeModelInfo(for: modelID) else {
            return []
        }

        var seen: Set<ReasoningLevel> = []
        return model.supportedReasoningEfforts.compactMap { option in
            guard let level = reasoningLevelIfKnown(option.reasoningEffort),
                  seen.insert(level).inserted
            else {
                return nil
            }
            return level
        }
    }

    func clampedReasoningLevel(_ level: ReasoningLevel, forModelID modelID: String?) -> ReasoningLevel {
        let supported = supportedReasoningLevels(forModelID: modelID)
        if supported.isEmpty {
            let inferred = inferredReasoningLevels(forModelID: modelID)
            guard !inferred.isEmpty else {
                return level
            }

            if inferred.contains(level) {
                return level
            }

            return inferred.first ?? level
        }

        if supported.contains(level) {
            return level
        }

        return defaultReasoningForModel(modelID) ?? supported.first ?? level
    }

    func defaultWebSearchForModel(_ modelID: String?) -> ProjectWebSearchMode? {
        if let model = runtimeModelInfo(for: modelID) {
            if let defaultWebSearchMode = model.defaultWebSearchMode {
                return mapProjectWebSearchMode(defaultWebSearchMode)
            }

            let supported = supportedWebSearchModes(forModelID: model.id)
            return supported.first
        }

        let inferred = inferredWebSearchModes(forModelID: modelID)
        return inferred.first
    }

    func clampedWebSearchMode(_ mode: ProjectWebSearchMode, forModelID modelID: String?) -> ProjectWebSearchMode {
        let supported = supportedWebSearchModes(forModelID: modelID)
        guard !supported.isEmpty else {
            return mode
        }

        if supported.contains(mode) {
            return mode
        }

        return defaultWebSearchForModel(modelID) ?? supported.first ?? mode
    }

    func configuredModelOverride() -> String? {
        let rawModel = codexConfigDocument.value(at: [.key("model")])?.stringValue
        let trimmedModel = rawModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedModel, !trimmedModel.isEmpty else {
            return nil
        }
        return trimmedModel
    }

    func configuredReasoningOverride() -> String? {
        let rawReasoning = codexConfigDocument.value(at: [.key("model_reasoning_effort")])?.stringValue
        let trimmedReasoning = rawReasoning?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedReasoning, !trimmedReasoning.isEmpty else {
            return nil
        }
        return trimmedReasoning
    }

    private func runtimeModelInfo(for modelID: String?) -> RuntimeModelInfo? {
        let trimmedModelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedModelID.isEmpty else {
            return nil
        }

        return runtimeModelCatalog.first { model in
            model.id == trimmedModelID || model.model == trimmedModelID
        }
    }

    private func isAPIKeyOnlyModel(_ modelID: String) -> Bool {
        modelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("gpt-4o") == .orderedSame
    }

    private func isSignedInWithChatGPTAuth() -> Bool {
        switch accountState.authMode {
        case .chatGPT, .chatGPTAuthTokens:
            return accountState.account != nil
        default:
            break
        }

        guard let account = accountState.account else {
            return false
        }

        return account.type.caseInsensitiveCompare("chatgpt") == .orderedSame
    }

    private func persistPreferredRuntimeModelPreference(_ modelID: String) {
        guard let preferenceRepository else {
            return
        }

        let persistedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await preferenceRepository.setPreference(
                    key: .runtimeDefaultModel,
                    value: persistedModelID
                )
            } catch {
                appendLog(.warning, "Failed to persist preferred model: \(error.localizedDescription)")
            }
        }
    }

    private func normalizeModelPresetIDs(_ modelIDs: [String]) -> [String] {
        var seen: Set<String> = []
        var normalized: [String] = []

        for rawModelID in modelIDs {
            let modelID = rawModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelID.isEmpty else {
                continue
            }

            let lowered = modelID.lowercased()
            guard seen.insert(lowered).inserted else {
                continue
            }
            normalized.append(modelID)
        }

        if seen.insert("gpt-4o").inserted {
            normalized.append("gpt-4o")
        }

        return normalized
    }

    private func matchingModelPreset(_ modelID: String, in presets: [String]) -> String? {
        presets.first { preset in
            preset.caseInsensitiveCompare(modelID) == .orderedSame
        }
    }

    private func canonicalModelLabel(_ label: String) -> String {
        var canonical = capitalizeModelTokenStarts(in: label)

        let replacements: [(String, String)] = [
            (#"(?i)\bgpt\b"#, "GPT"),
            (#"(?i)\bcodex\b"#, "Codex"),
        ]

        for (pattern, replacement) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(canonical.startIndex ..< canonical.endIndex, in: canonical)
            canonical = regex.stringByReplacingMatches(
                in: canonical,
                options: [],
                range: range,
                withTemplate: replacement
            )
        }

        return canonical
    }

    private func capitalizeModelTokenStarts(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        var shouldCapitalize = true
        for scalar in text.unicodeScalars {
            let character = Character(scalar)
            if shouldCapitalize, character.isLowercaseASCII {
                result.append(String(character).uppercased())
            } else {
                result.append(character)
            }

            shouldCapitalize = scalar == "-" || scalar == " "
        }

        return result
    }

    private func supportedWebSearchModes(forModelID modelID: String?) -> [ProjectWebSearchMode] {
        if let model = runtimeModelInfo(for: modelID) {
            if let supportedWebSearchModes = model.supportedWebSearchModes {
                let mapped = uniqueWebSearchModes(supportedWebSearchModes.map(mapProjectWebSearchMode))
                if !mapped.isEmpty {
                    return mapped
                }
            }

            if let defaultWebSearchMode = model.defaultWebSearchMode {
                return [mapProjectWebSearchMode(defaultWebSearchMode)]
            }
        }

        return inferredWebSearchModes(forModelID: modelID)
    }

    private func inferredReasoningLevels(forModelID modelID: String?) -> [ReasoningLevel] {
        let normalizedModelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !normalizedModelID.isEmpty else {
            return []
        }

        if normalizedModelID.hasPrefix("gpt-4o") {
            return [.none]
        }

        return []
    }

    private func canChooseReasoning(forModelID modelID: String?) -> Bool {
        let supported = supportedReasoningLevels(forModelID: modelID)
        if !supported.isEmpty {
            return supported.count > 1
        }

        let inferred = inferredReasoningLevels(forModelID: modelID)
        if !inferred.isEmpty {
            return inferred.count > 1
        }

        return true
    }

    private func inferredWebSearchModes(forModelID modelID: String?) -> [ProjectWebSearchMode] {
        let normalizedModelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !normalizedModelID.isEmpty else {
            return []
        }

        if normalizedModelID.hasPrefix("gpt-4o") {
            return [.disabled]
        }

        return []
    }

    private func uniqueWebSearchModes(_ modes: [ProjectWebSearchMode]) -> [ProjectWebSearchMode] {
        var seen: Set<ProjectWebSearchMode> = []
        return modes
            .filter { seen.insert($0).inserted }
            .sorted { webSearchRank($0) < webSearchRank($1) }
    }

    private func mapProjectWebSearchMode(_ mode: RuntimeWebSearchMode) -> ProjectWebSearchMode {
        switch mode {
        case .disabled: .disabled
        case .cached: .cached
        case .live: .live
        }
    }

    private func reasoningLevelsFromSchema() -> [ReasoningLevel] {
        let schemaEnumValues = codexConfigSchema
            .node(at: [.key("model_reasoning_effort")])?
            .enumValues ?? []

        var seen: Set<ReasoningLevel> = []
        return schemaEnumValues
            .compactMap(reasoningLevelIfKnown)
            .filter { seen.insert($0).inserted }
            .sorted { reasoningRank($0) < reasoningRank($1) }
    }

    private func reasoningRank(_ level: ReasoningLevel) -> Int {
        switch level {
        case .none:
            0
        case .minimal:
            1
        case .low:
            2
        case .medium:
            3
        case .high:
            4
        case .xhigh:
            5
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
        let effectiveModel = configuredModelOverride()
        let selectedModelID = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let effort: String?
        if let configuredReasoning = configuredReasoningOverride(),
           let mappedReasoning = reasoningLevelIfKnown(configuredReasoning)
        {
            let clampedReasoning = clampedReasoningLevel(mappedReasoning, forModelID: selectedModelID)
            effort = canChooseReasoning(forModelID: selectedModelID) ? clampedReasoning.rawValue : nil
        } else {
            effort = nil
        }

        return RuntimeTurnOptions(
            model: effectiveModel,
            effort: effort,
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

private extension Character {
    var isLowercaseASCII: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else {
            return false
        }

        return scalar.value >= 97 && scalar.value <= 122
    }
}
