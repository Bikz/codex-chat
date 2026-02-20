import Foundation

extension AppModel {
    func onAppear() {
        startRuntimePoolMetricsLoopIfNeeded()
        Task {
            await loadInitialData()
        }
    }

    func retryLoad() {
        Task {
            await loadInitialData()
        }
    }

    func restartRuntime() {
        Task {
            await restartRuntimeSession()
        }
    }

    func loadInitialData() async {
        let startupGeneration = beginStartupLoadGeneration()
        appendLog(.info, "Loading initial metadata")
        projectsState = .loading

        do {
            try await runStartupCriticalPhase(generation: startupGeneration)
        } catch {
            guard isCurrentStartupGeneration(startupGeneration) else {
                return
            }
            let message = error.localizedDescription
            projectsState = .failed(message)
            threadsState = .failed(message)
            archivedThreadsState = .failed(message)
            conversationState = .failed(message)
            skillsState = .failed(message)
            runtimeStatus = .error
            runtimeIssue = .recoverable(message)
            enterOnboarding(reason: .startup)
            appendLog(.error, "Failed to load initial data: \(message)")
            return
        }

        scheduleStartupBackgroundPhase(generation: startupGeneration)
        guard isCurrentStartupGeneration(startupGeneration) else {
            return
        }

        await startRuntimeSession()
        guard isCurrentStartupGeneration(startupGeneration) else {
            return
        }

        if isOnboardingReadyToComplete {
            completeOnboardingIfReady()
        } else {
            enterOnboarding(reason: .startup)
        }
    }

    private func runStartupCriticalPhase(generation: UInt64) async throws {
        try await refreshProjects()
        try ensureCurrentStartupGeneration(generation)

        try await applyStartupStorageFixups()
        try ensureCurrentStartupGeneration(generation)

        do {
            try await loadCodexConfig()
        } catch {
            replaceCodexConfigDocument(.empty())
            codexConfigValidationIssues = []
            codexConfigStatusMessage = "Failed to load config.toml. Using built-in defaults: \(error.localizedDescription)"
            appendLog(
                .warning,
                "Failed loading config.toml; continuing with built-in defaults: \(error.localizedDescription)"
            )
        }
        try ensureCurrentStartupGeneration(generation)

        await reloadCodexConfigSchema()
        try ensureCurrentStartupGeneration(generation)

        try await ensureGeneralProject()
        try ensureCurrentStartupGeneration(generation)

        try await restoreLastOpenedContext()
        try ensureCurrentStartupGeneration(generation)

        try await restoreTranscriptDetailLevelPreference()
        try ensureCurrentStartupGeneration(generation)

        await restoreWorkerTraceCacheIfNeeded()
        try ensureCurrentStartupGeneration(generation)

        await restoreUserThemeCustomizationIfNeeded()
        try ensureCurrentStartupGeneration(generation)

        await restoreModsBarVisibility()
        try ensureCurrentStartupGeneration(generation)

        try await validateAndRepairProjectsOnLaunch()
        try ensureCurrentStartupGeneration(generation)

        try await refreshThreads(refreshSelectedThreadFollowUpQueue: false)
        try ensureCurrentStartupGeneration(generation)

        ensureGeneralDraftChatSelectionIfNeeded()
        try ensureCurrentStartupGeneration(generation)

        if let selectedThreadID {
            scheduleStartupSelectedThreadHydration(
                threadID: selectedThreadID,
                generation: generation
            )
        }

        refreshConversationState()
        appendLog(.info, "Initial metadata critical load completed")
    }

    private func scheduleStartupBackgroundPhase(generation: UInt64) {
        startupBackgroundTask?.cancel()
        startupBackgroundTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await runStartupBackgroundPhase(generation: generation)
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentStartupGeneration(generation) else {
                    return
                }
                appendLog(.warning, "Startup background hydration failed: \(error.localizedDescription)")
            }
        }
    }

    private func runStartupBackgroundPhase(generation: UInt64) async throws {
        try ensureCurrentStartupGeneration(generation)

        refreshModsSurface()

        async let generalThreadsTask: Void = refreshGeneralThreads()
        async let archivedThreadsTask: Void = refreshArchivedThreads()
        async let followUpsTask: Void = refreshFollowUpQueuesForVisibleThreads()
        async let skillsTask: Void = refreshSkills()
        async let skillsCatalogTask: Void = refreshSkillsCatalog()
        async let advancedModsTask: Void = restoreAdvancedExecutableModsUnlockIfNeeded()
        async let titleBackfillTask: Void = runThreadTitleIndexBackfillIfNeeded(generation: generation)

        _ = try await (generalThreadsTask, archivedThreadsTask, followUpsTask, skillsTask)
        try ensureCurrentStartupGeneration(generation)

        await skillsCatalogTask
        await advancedModsTask
        await titleBackfillTask
        try ensureCurrentStartupGeneration(generation)

        appendLog(.info, "Initial metadata background hydration completed")
    }

    private func runThreadTitleIndexBackfillIfNeeded(generation: UInt64) async {
        guard let preferenceRepository,
              let projectRepository,
              let threadRepository
        else {
            return
        }

        do {
            let didBackfill = try await preferenceRepository.getPreference(key: .threadTitleIndexBackfillV1) == "1"
            guard !didBackfill else {
                return
            }
            try ensureCurrentStartupGeneration(generation)

            let allProjects = try await projectRepository.listProjects()
            for project in allProjects {
                try ensureCurrentStartupGeneration(generation)
                let allThreads = try await threadRepository.listThreads(projectID: project.id, scope: .all)
                for thread in allThreads {
                    try ensureCurrentStartupGeneration(generation)
                    try await chatSearchRepository?.indexThreadTitle(
                        threadID: thread.id,
                        projectID: project.id,
                        title: thread.title
                    )
                }
            }

            try ensureCurrentStartupGeneration(generation)
            try await preferenceRepository.setPreference(key: .threadTitleIndexBackfillV1, value: "1")
            appendLog(.debug, "Completed one-time thread title search index backfill.")
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentStartupGeneration(generation) else {
                return
            }
            appendLog(.warning, "Thread title index backfill failed: \(error.localizedDescription)")
        }
    }

    private func beginStartupLoadGeneration() -> UInt64 {
        startupBackgroundTask?.cancel()
        startupLoadGeneration = startupLoadGeneration &+ 1
        return startupLoadGeneration
    }

    private func scheduleStartupSelectedThreadHydration(threadID: UUID, generation: UInt64) {
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            guard isCurrentStartupGeneration(generation) else { return }

            await rehydrateThreadTranscript(threadID: threadID)
            guard !Task.isCancelled else { return }
            guard isCurrentStartupGeneration(generation) else { return }
            guard selectedThreadID == threadID else { return }

            refreshConversationStateIfSelectedThreadChanged(threadID)
        }
    }

    private func isCurrentStartupGeneration(_ generation: UInt64) -> Bool {
        startupLoadGeneration == generation
    }

    private func ensureCurrentStartupGeneration(_ generation: UInt64) throws {
        guard isCurrentStartupGeneration(generation) else {
            throw CancellationError()
        }
    }
}
