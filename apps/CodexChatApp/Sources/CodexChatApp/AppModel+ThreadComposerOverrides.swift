import CodexChatCore
import Foundation

private struct PersistedThreadComposerOverridesV1: Codable {
    var byThreadID: [String: AppModel.ThreadComposerOverride]
}

extension AppModel {
    func requestSettingsNavigationToProjects(projectID: UUID?) {
        settingsNavigationTarget = SettingsNavigationTarget(section: .projects, projectID: projectID)
    }

    func consumeSettingsNavigationTarget() -> SettingsNavigationTarget? {
        defer {
            settingsNavigationTarget = nil
        }
        return settingsNavigationTarget
    }

    func setComposerWebSearchOverrideForCurrentContext(_ mode: ProjectWebSearchMode) {
        let inherited = inheritedWebSearchModeForCurrentContext()
        let normalized: ProjectWebSearchMode? = mode == inherited ? nil : mode

        mutateCurrentContextComposerOverride { override in
            override.webSearchOverride = normalized

            if var safetyOverride = override.safetyOverride {
                safetyOverride.webSearch = mode
                override.safetyOverride = safetyOverride
            }
        }
    }

    func setComposerMemoryModeOverrideForCurrentContext(_ mode: ComposerMemoryMode) {
        let normalized: ComposerMemoryMode? = mode == .projectDefault ? nil : mode

        mutateCurrentContextComposerOverride { override in
            override.memoryModeOverride = normalized
        }
    }

    func setComposerSafetyOverrideForCurrentContext(
        sandboxMode: ProjectSandboxMode,
        approvalPolicy: ProjectApprovalPolicy,
        networkAccess: Bool
    ) {
        let inherited = inheritedSafetySettingsForCurrentContext()
        var settings = ProjectSafetySettings(
            sandboxMode: sandboxMode,
            approvalPolicy: approvalPolicy,
            networkAccess: networkAccess,
            webSearch: composerWebSearchModeForCurrentContext
        )

        // Preserve selected web override in the tuple so resolving is deterministic.
        settings.webSearch = composerWebSearchModeForCurrentContext

        let normalized: ProjectSafetySettings? = settings == inherited ? nil : settings

        mutateCurrentContextComposerOverride { override in
            override.safetyOverride = normalized
        }
    }

    func clearComposerOverridesForCurrentContext() {
        mutateCurrentContextComposerOverride { override in
            override.webSearchOverride = nil
            override.memoryModeOverride = nil
            override.safetyOverride = nil
        }
    }

    var composerWebSearchModeForCurrentContext: ProjectWebSearchMode {
        currentContextComposerOverride?.webSearchOverride ?? inheritedWebSearchModeForCurrentContext()
    }

    var composerSafetySettingsForCurrentContext: ProjectSafetySettings {
        currentContextComposerOverride?.safetyOverride ?? inheritedSafetySettingsForCurrentContext()
    }

    var hasComposerOverrideForCurrentContext: Bool {
        currentContextComposerOverride?.isEmpty == false
    }

    var hasComposerSafetyOverrideForCurrentContext: Bool {
        currentContextComposerOverride?.safetyOverride != nil
    }

    var hasComposerWebSearchOverrideForCurrentContext: Bool {
        currentContextComposerOverride?.webSearchOverride != nil
    }

    var hasComposerMemoryOverrideForCurrentContext: Bool {
        currentContextComposerOverride?.memoryModeOverride != nil
    }

    func syncComposerOverridesForCurrentSelection() {
        let selectedMode = currentContextComposerOverride?.memoryModeOverride ?? .projectDefault
        if composerMemoryMode != selectedMode {
            composerMemoryMode = selectedMode
        }
    }

    func restoreThreadComposerOverridesIfNeeded() async throws {
        guard let preferenceRepository else {
            threadComposerOverridesByThreadID = [:]
            syncComposerOverridesForCurrentSelection()
            return
        }

        guard let raw = try await preferenceRepository.getPreference(key: .threadComposerOverridesV1),
              let data = raw.data(using: .utf8)
        else {
            threadComposerOverridesByThreadID = [:]
            syncComposerOverridesForCurrentSelection()
            return
        }

        if let decoded = try? JSONDecoder().decode(PersistedThreadComposerOverridesV1.self, from: data) {
            threadComposerOverridesByThreadID = Dictionary(
                uniqueKeysWithValues: decoded.byThreadID.compactMap { key, value in
                    guard let threadID = UUID(uuidString: key) else {
                        return nil
                    }
                    return (threadID, value)
                }
            )
            syncComposerOverridesForCurrentSelection()
            return
        }

        if let legacyMap = try? JSONDecoder().decode([String: ThreadComposerOverride].self, from: data) {
            threadComposerOverridesByThreadID = Dictionary(
                uniqueKeysWithValues: legacyMap.compactMap { key, value in
                    guard let threadID = UUID(uuidString: key) else {
                        return nil
                    }
                    return (threadID, value)
                }
            )
            syncComposerOverridesForCurrentSelection()
            return
        }

        appendLog(.warning, "Failed to decode thread composer overrides; clearing persisted value.")
        threadComposerOverridesByThreadID = [:]
        syncComposerOverridesForCurrentSelection()
    }

    func persistThreadComposerOverridesPreference() async throws {
        guard let preferenceRepository else {
            return
        }

        let persisted = PersistedThreadComposerOverridesV1(
            byThreadID: Dictionary(
                uniqueKeysWithValues: threadComposerOverridesByThreadID.map { threadID, override in
                    (threadID.uuidString, override)
                }
            )
        )
        let data = try JSONEncoder().encode(persisted)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try await preferenceRepository.setPreference(key: .threadComposerOverridesV1, value: text)
    }

    func materializeDraftComposerOverrideIfNeeded(into threadID: UUID) {
        guard let draftComposerOverride, !draftComposerOverride.isEmpty else {
            return
        }

        threadComposerOverridesByThreadID[threadID] = draftComposerOverride
        self.draftComposerOverride = nil
        syncComposerOverridesForCurrentSelection()

        Task {
            do {
                try await persistThreadComposerOverridesPreference()
            } catch {
                appendLog(.warning, "Failed to persist thread composer overrides: \(error.localizedDescription)")
            }
        }
    }

    func pruneStaleThreadComposerOverrides(validThreadIDs: Set<UUID>) {
        let previousCount = threadComposerOverridesByThreadID.count
        threadComposerOverridesByThreadID = threadComposerOverridesByThreadID.filter { validThreadIDs.contains($0.key) }
        guard threadComposerOverridesByThreadID.count != previousCount else {
            return
        }

        Task {
            do {
                try await persistThreadComposerOverridesPreference()
            } catch {
                appendLog(.warning, "Failed to persist pruned thread composer overrides: \(error.localizedDescription)")
            }
        }
    }

    func pruneThreadComposerOverridesAgainstLoadedThreads() {
        let validIDs = Set((threads + generalThreads + archivedThreads).map(\.id))
        pruneStaleThreadComposerOverrides(validThreadIDs: validIDs)
    }

    func pruneThreadComposerOverridesAgainstRepositorySnapshotIfNeeded() async {
        guard let projectRepository,
              let threadRepository
        else {
            return
        }

        do {
            let projects = try await projectRepository.listProjects()
            var validThreadIDs: Set<UUID> = []
            validThreadIDs.reserveCapacity(threadComposerOverridesByThreadID.count)

            for project in projects {
                let allThreads = try await threadRepository.listThreads(projectID: project.id, scope: .all)
                validThreadIDs.formUnion(allThreads.map(\.id))
            }

            pruneStaleThreadComposerOverrides(validThreadIDs: validThreadIDs)
        } catch {
            appendLog(.warning, "Failed pruning stale thread composer overrides: \(error.localizedDescription)")
        }
    }

    func effectiveWebSearchMode(for threadID: UUID?, project: ProjectRecord?) -> ProjectWebSearchMode {
        if let threadID,
           let override = threadComposerOverridesByThreadID[threadID]?.webSearchOverride
        {
            return override
        }

        return project?.webSearch ?? defaultWebSearch
    }

    func effectiveComposerMemoryWriteMode(for project: ProjectRecord?, threadID: UUID?) -> ProjectMemoryWriteMode {
        let mode = threadID
            .flatMap { threadComposerOverridesByThreadID[$0]?.memoryModeOverride }
            ?? .projectDefault

        switch mode {
        case .projectDefault:
            return project?.memoryWriteMode ?? .off
        case .off:
            return .off
        case .summariesOnly:
            return .summariesOnly
        case .summariesAndKeyFacts:
            return .summariesAndKeyFacts
        }
    }

    func effectiveSafetySettings(for threadID: UUID?, project: ProjectRecord) -> ProjectSafetySettings {
        if let threadID,
           let override = threadComposerOverridesByThreadID[threadID]?.safetyOverride
        {
            return override
        }

        return ProjectSafetySettings(
            sandboxMode: project.sandboxMode,
            approvalPolicy: project.approvalPolicy,
            networkAccess: project.networkAccess,
            webSearch: project.webSearch
        )
    }

    private var currentContextComposerOverride: ThreadComposerOverride? {
        if let selectedThreadID {
            return threadComposerOverridesByThreadID[selectedThreadID]
        }

        if hasActiveDraftChatForSelectedProject {
            return draftComposerOverride
        }

        return nil
    }

    private func inheritedWebSearchModeForCurrentContext() -> ProjectWebSearchMode {
        selectedProject?.webSearch ?? defaultWebSearch
    }

    private func inheritedSafetySettingsForCurrentContext() -> ProjectSafetySettings {
        guard let project = selectedProject else {
            return defaultSafetySettings
        }

        return ProjectSafetySettings(
            sandboxMode: project.sandboxMode,
            approvalPolicy: project.approvalPolicy,
            networkAccess: project.networkAccess,
            webSearch: project.webSearch
        )
    }

    private func mutateCurrentContextComposerOverride(_ mutate: (inout ThreadComposerOverride) -> Void) {
        guard selectedThreadID != nil || hasActiveDraftChatForSelectedProject else {
            return
        }

        var override = currentContextComposerOverride ?? ThreadComposerOverride()
        mutate(&override)

        if let selectedThreadID {
            if override.isEmpty {
                threadComposerOverridesByThreadID.removeValue(forKey: selectedThreadID)
            } else {
                threadComposerOverridesByThreadID[selectedThreadID] = override
            }
        } else {
            draftComposerOverride = override.isEmpty ? nil : override
        }

        syncComposerOverridesForCurrentSelection()

        Task {
            do {
                try await persistThreadComposerOverridesPreference()
            } catch {
                appendLog(.warning, "Failed to persist thread composer overrides: \(error.localizedDescription)")
            }
        }
    }
}
