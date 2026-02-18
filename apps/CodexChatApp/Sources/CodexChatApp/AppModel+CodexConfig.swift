import CodexChatCore
import Foundation

extension AppModel {
    func loadCodexConfig() async throws {
        isCodexConfigBusy = true
        defer { isCodexConfigBusy = false }

        let loadedDocument = try codexConfigFileStore.load()
        codexConfigDocument = loadedDocument

        try await migrateLegacyRuntimePreferencesIntoConfigIfNeeded()
        applyDerivedRuntimeDefaultsFromConfig()
    }

    func reloadCodexConfigSchema() async {
        do {
            let payload = try await codexConfigSchemaLoader.load()
            let normalizer = try CodexConfigSchemaNormalizer(data: payload.data)
            codexConfigSchema = normalizer.normalize()
            codexConfigSchemaSource = payload.source
        } catch {
            codexConfigStatusMessage = "Failed to load Codex config schema: \(error.localizedDescription)"
            appendLog(.warning, "Failed loading Codex config schema: \(error.localizedDescription)")
        }
    }

    func updateCodexConfigValue(path: [CodexConfigPathSegment], value: CodexConfigValue?) {
        var document = codexConfigDocument
        document.setValue(value, at: path)
        codexConfigDocument = document
        applyDerivedRuntimeDefaultsFromConfig()
    }

    func replaceCodexConfigDocument(_ document: CodexConfigDocument) {
        codexConfigDocument = document
        applyDerivedRuntimeDefaultsFromConfig()
    }

    func saveCodexConfigAndRestartRuntime() async {
        await saveCodexConfig(restartRuntime: true)
    }

    func saveCodexConfig(restartRuntime: Bool = false) async {
        isCodexConfigBusy = true
        defer { isCodexConfigBusy = false }

        let issues = codexConfigValidator.validate(value: codexConfigDocument.root, against: codexConfigSchema)
        codexConfigValidationIssues = issues
        if issues.contains(where: { $0.severity == .error }) {
            codexConfigStatusMessage = "Cannot save config.toml until schema errors are fixed."
            return
        }

        do {
            var document = codexConfigDocument
            let saveResult = try codexConfigFileStore.save(document: document)
            try document.syncRawFromRoot()
            document.fileHash = saveResult.hash
            document.fileModifiedAt = saveResult.modifiedAt
            codexConfigDocument = document
            applyDerivedRuntimeDefaultsFromConfig()

            if restartRuntime, runtime != nil {
                codexConfigStatusMessage = "Saved config.toml. Restarting runtime…"
                await restartRuntimeSession()
                codexConfigStatusMessage = "Saved config.toml and restarted runtime."
            } else if restartRuntime {
                codexConfigStatusMessage = "Saved config.toml. Changes apply on next runtime start."
            } else {
                codexConfigStatusMessage = "Saved config.toml."
            }
        } catch {
            codexConfigStatusMessage = "Failed to save config.toml: \(error.localizedDescription)"
            appendLog(.error, "Failed saving config.toml: \(error.localizedDescription)")
        }
    }

    func parseCodexConfigRaw(_ rawText: String) throws -> CodexConfigDocument {
        var document = try CodexConfigDocument.parse(rawText: rawText)
        document.fileHash = codexConfigDocument.fileHash
        document.fileModifiedAt = codexConfigDocument.fileModifiedAt
        return document
    }

    func writeCodexConfigWithoutRestart() async {
        await saveCodexConfig(restartRuntime: false)
    }

    private func applyDerivedRuntimeDefaultsFromConfig() {
        if let model = codexConfigDocument.value(at: [.key("model")])?.stringValue,
           !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            defaultModel = model
        }

        if let reasoning = codexConfigDocument.value(at: [.key("model_reasoning_effort")])?.stringValue {
            defaultReasoning = mapReasoningLevel(reasoning)
        }

        if let webSearch = codexConfigDocument.value(at: [.key("web_search")])?.stringValue,
           let mode = ProjectWebSearchMode(rawValue: webSearch)
        {
            defaultWebSearch = mode
        }

        let sandboxMode = codexConfigDocument
            .value(at: [.key("sandbox_mode")])?
            .stringValue
            .flatMap(mapProjectSandboxMode) ?? .readOnly

        let approvalPolicy = codexConfigDocument
            .value(at: [.key("approval_policy")])?
            .stringValue
            .flatMap(mapProjectApprovalPolicy) ?? .untrusted

        let networkAccess = codexConfigDocument
            .value(at: [.key("sandbox_workspace_write"), .key("network_access")])?
            .booleanValue ?? false

        let webSearchMode = codexConfigDocument
            .value(at: [.key("web_search")])?
            .stringValue
            .flatMap(ProjectWebSearchMode.init(rawValue:)) ?? .cached

        defaultSafetySettings = ProjectSafetySettings(
            sandboxMode: sandboxMode,
            approvalPolicy: approvalPolicy,
            networkAccess: networkAccess,
            webSearch: webSearchMode
        )
    }

    private func migrateLegacyRuntimePreferencesIntoConfigIfNeeded() async throws {
        guard let preferenceRepository else {
            return
        }

        let alreadyMigrated = try await preferenceRepository.getPreference(key: .runtimeConfigMigrationV1) == "1"
        if alreadyMigrated {
            return
        }

        var document = codexConfigDocument
        var didChange = false

        if document.value(at: [.key("model")]) == nil,
           let legacyModel = try await preferenceRepository.getPreference(key: .runtimeDefaultModel),
           !legacyModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            document.setValue(.string(legacyModel), at: [.key("model")])
            didChange = true
        }

        if document.value(at: [.key("model_reasoning_effort")]) == nil,
           let legacyReasoning = try await preferenceRepository.getPreference(key: .runtimeDefaultReasoning),
           !legacyReasoning.isEmpty
        {
            document.setValue(.string(legacyReasoning), at: [.key("model_reasoning_effort")])
            didChange = true
        }

        if document.value(at: [.key("web_search")]) == nil,
           let legacyWebSearch = try await preferenceRepository.getPreference(key: .runtimeDefaultWebSearch),
           !legacyWebSearch.isEmpty
        {
            document.setValue(.string(legacyWebSearch), at: [.key("web_search")])
            didChange = true
        }

        if let legacySafety = try await preferenceRepository.getPreference(key: .runtimeDefaultSafety),
           let data = legacySafety.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ProjectSafetySettings.self, from: data)
        {
            if document.value(at: [.key("sandbox_mode")]) == nil {
                document.setValue(.string(mapSandboxModeString(decoded.sandboxMode)), at: [.key("sandbox_mode")])
                didChange = true
            }

            if document.value(at: [.key("approval_policy")]) == nil {
                document.setValue(.string(mapApprovalPolicyString(decoded.approvalPolicy)), at: [.key("approval_policy")])
                didChange = true
            }

            if document.value(at: [.key("web_search")]) == nil {
                document.setValue(.string(decoded.webSearch.rawValue), at: [.key("web_search")])
                didChange = true
            }

            if document.value(at: [.key("sandbox_workspace_write"), .key("network_access")]) == nil {
                document.setValue(
                    .boolean(decoded.networkAccess),
                    at: [.key("sandbox_workspace_write"), .key("network_access")]
                )
                didChange = true
            }
        }

        if didChange {
            codexConfigDocument = document
            applyDerivedRuntimeDefaultsFromConfig()
            _ = try codexConfigFileStore.save(document: document)
            appendLog(.info, "Migrated legacy runtime defaults into config.toml")
        }

        try await preferenceRepository.setPreference(key: .runtimeConfigMigrationV1, value: "1")
    }

    private func mapReasoningLevel(_ value: String) -> ReasoningLevel {
        switch value.lowercased() {
        case "high", "xhigh":
            .high
        case "low", "minimal", "none":
            .low
        default:
            .medium
        }
    }

    private func mapProjectSandboxMode(_ value: String) -> ProjectSandboxMode? {
        switch value {
        case "read-only":
            .readOnly
        case "workspace-write":
            .workspaceWrite
        case "danger-full-access":
            .dangerFullAccess
        default:
            nil
        }
    }

    private func mapProjectApprovalPolicy(_ value: String) -> ProjectApprovalPolicy? {
        switch value {
        case "untrusted":
            .untrusted
        case "on-request":
            .onRequest
        case "never":
            .never
        default:
            nil
        }
    }

    func mapSandboxModeString(_ mode: ProjectSandboxMode) -> String {
        switch mode {
        case .readOnly:
            "read-only"
        case .workspaceWrite:
            "workspace-write"
        case .dangerFullAccess:
            "danger-full-access"
        }
    }

    func mapApprovalPolicyString(_ policy: ProjectApprovalPolicy) -> String {
        switch policy {
        case .untrusted:
            "untrusted"
        case .onRequest:
            "on-request"
        case .never:
            "never"
        }
    }
}
