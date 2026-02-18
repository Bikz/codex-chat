import AppKit
import CodexChatCore
import CodexMemory
import Foundation

extension AppModel {
    func validateAndRepairProjectsOnLaunch() async throws {
        let allProjects = projects
        guard !allProjects.isEmpty else {
            return
        }

        var missingProjectIDs: Set<UUID> = []
        var repairedProjectCount = 0

        for project in allProjects {
            if project.isGeneralProject {
                try await prepareProjectFolderStructure(projectPath: project.path)
                repairedProjectCount += 1
                continue
            }

            guard Self.projectDirectoryExists(path: project.path) else {
                missingProjectIDs.insert(project.id)
                appendLog(
                    .warning,
                    "Project path is missing at launch: \(project.path) (project \(project.name))"
                )
                continue
            }

            try await prepareProjectFolderStructure(projectPath: project.path)
            repairedProjectCount += 1
        }

        var didAdjustSelection = false
        let fallbackProjectID = launchFallbackProjectID(
            projects: allProjects,
            missingProjectIDs: missingProjectIDs
        )

        if let selectedProjectID {
            let isSelectedProjectHealthy = allProjects.contains {
                $0.id == selectedProjectID && !missingProjectIDs.contains($0.id)
            }
            if !isSelectedProjectHealthy {
                self.selectedProjectID = fallbackProjectID
                selectedThreadID = nil
                didAdjustSelection = true
                appendLog(
                    .warning,
                    "Selected project became unavailable. Switched to fallback project."
                )
            }
        } else if let fallbackProjectID {
            selectedProjectID = fallbackProjectID
            didAdjustSelection = true
        }

        if let selectedThreadID,
           let threadRepository
        {
            let restoredThread = try await threadRepository.getThread(id: selectedThreadID)
            let isThreadValid = restoredThread.map { $0.projectId == self.selectedProjectID } ?? false
            if !isThreadValid {
                self.selectedThreadID = nil
                didAdjustSelection = true
                appendLog(.warning, "Cleared stale thread selection during launch health check.")
            }
        }

        if didAdjustSelection {
            try await persistSelection()
        }

        if !missingProjectIDs.isEmpty {
            let missingCount = missingProjectIDs.count
            let noun = missingCount == 1 ? "project folder was" : "project folders were"
            projectStatusMessage = "\(missingCount) \(noun) not found. Re-open moved projects from disk."
        } else if repairedProjectCount > 0 {
            appendLog(.debug, "Launch health check repaired project structure for \(repairedProjectCount) project(s).")
        }
    }

    func showProjectSettings() {
        isProjectSettingsVisible = true
    }

    func closeProjectSettings() {
        isProjectSettingsVisible = false
    }

    func requiresDangerConfirmation(
        sandboxMode: ProjectSandboxMode,
        approvalPolicy: ProjectApprovalPolicy
    ) -> Bool {
        sandboxMode == .dangerFullAccess || approvalPolicy == .never
    }

    var dangerConfirmationPhrase: String {
        "ENABLE UNSAFE MODE"
    }

    func updateSelectedProjectSafetySettings(
        sandboxMode: ProjectSandboxMode,
        approvalPolicy: ProjectApprovalPolicy,
        networkAccess: Bool,
        webSearch: ProjectWebSearchMode
    ) {
        guard let selectedProjectID,
              let projectRepository
        else {
            return
        }

        let settings = ProjectSafetySettings(
            sandboxMode: sandboxMode,
            approvalPolicy: approvalPolicy,
            networkAccess: networkAccess,
            webSearch: webSearch
        )

        Task {
            do {
                _ = try await projectRepository.updateProjectSafetySettings(
                    id: selectedProjectID,
                    settings: settings
                )
                try await refreshProjects()
                projectStatusMessage = "Updated safety settings for this project."
            } catch {
                projectStatusMessage = "Failed to update safety settings: \(error.localizedDescription)"
                appendLog(.error, "Failed to update safety settings: \(error.localizedDescription)")
            }
        }
    }

    func updateSelectedProjectMemorySettings(
        writeMode: ProjectMemoryWriteMode,
        embeddingsEnabled: Bool
    ) {
        guard let selectedProjectID,
              let projectRepository
        else {
            return
        }

        let settings = ProjectMemorySettings(writeMode: writeMode, embeddingsEnabled: embeddingsEnabled)
        Task {
            do {
                _ = try await projectRepository.updateProjectMemorySettings(
                    id: selectedProjectID,
                    settings: settings
                )
                try await refreshProjects()
                memoryStatusMessage = "Updated memory settings for this project."
            } catch {
                memoryStatusMessage = "Failed to update memory settings: \(error.localizedDescription)"
                appendLog(.error, "Failed to update memory settings: \(error.localizedDescription)")
            }
        }
    }

    func openSafetyPolicyDocument() {
        let url = Bundle.module.url(forResource: "SafetyPolicy", withExtension: "md")
            ?? Bundle.module.url(forResource: "SafetyPolicy", withExtension: "md", subdirectory: "Resources")
        guard let url else {
            projectStatusMessage = "Local safety document is unavailable."
            return
        }
        NSWorkspace.shared.open(url)
    }

    func trustSelectedProject() {
        setSelectedProjectTrustState(.trusted)
    }

    func untrustSelectedProject() {
        setSelectedProjectTrustState(.untrusted)
    }

    static func isGitProject(path: String) -> Bool {
        let gitDirectory = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent(".git", isDirectory: true)
            .path
        return FileManager.default.fileExists(atPath: gitDirectory)
    }

    static func projectDirectoryExists(
        path: String,
        fileManager: FileManager = .default
    ) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private func launchFallbackProjectID(
        projects: [ProjectRecord],
        missingProjectIDs: Set<UUID>
    ) -> UUID? {
        if let generalID = projects.first(where: { $0.isGeneralProject && !missingProjectIDs.contains($0.id) })?.id {
            return generalID
        }

        return projects.first(where: { !missingProjectIDs.contains($0.id) })?.id
    }

    private func setSelectedProjectTrustState(_ trustState: ProjectTrustState) {
        guard let selectedProjectID,
              let projectRepository
        else {
            return
        }

        Task {
            do {
                _ = try await projectRepository.updateProjectTrustState(id: selectedProjectID, trustState: trustState)
                try await refreshProjects()
                projectStatusMessage = trustState == .trusted
                    ? "Project trusted. Runtime can act with normal settings."
                    : "Project marked untrusted. Read-only is recommended."
            } catch {
                projectStatusMessage = "Failed to update trust state: \(error.localizedDescription)"
                appendLog(.error, "Failed to update trust state: \(error.localizedDescription)")
            }
        }
    }

    func prepareProjectFolderStructure(projectPath: String) async throws {
        let fileManager = FileManager.default
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)

        // Human-owned project artifacts.
        try fileManager.createDirectory(
            at: projectURL.appendingPathComponent("chats", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: projectURL.appendingPathComponent("artifacts", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: projectURL.appendingPathComponent("mods", isDirectory: true),
            withIntermediateDirectories: true
        )

        // Project-scoped skills live under .agents/skills (managed by the app, not the agent).
        try fileManager.createDirectory(
            at: projectURL.appendingPathComponent(".agents/skills", isDirectory: true),
            withIntermediateDirectories: true
        )

        let memoryStore = ProjectMemoryStore(projectPath: projectPath)
        try await memoryStore.ensureStructure()
    }

    func ensureSelectedProjectHasDefaultThread() async throws {
        guard let selectedProjectID,
              let threadRepository
        else {
            return
        }

        let threads = try await threadRepository.listThreads(projectID: selectedProjectID)
        if !threads.isEmpty {
            return
        }

        let title = "New chat"
        let thread = try await threadRepository.createThread(projectID: selectedProjectID, title: title)

        try await chatSearchRepository?.indexThreadTitle(
            threadID: thread.id,
            projectID: selectedProjectID,
            title: title
        )

        try await refreshThreads()
        selectedThreadID = thread.id
        try await persistSelection()
        try await refreshFollowUpQueue(threadID: thread.id)
        refreshConversationState()
        appendLog(.info, "Created default thread for project \(selectedProjectID.uuidString)")
    }

    func ensureGeneralProject() async throws {
        guard let projectRepository else { return }

        let generalURL = storagePaths.generalProjectURL
        try storagePaths.ensureRootStructure()
        try FileManager.default.createDirectory(at: generalURL, withIntermediateDirectories: true)

        // Check if a general project already exists.
        if var existing = projects.first(where: \.isGeneralProject) {
            if existing.path != generalURL.path {
                _ = try await projectRepository.updateProjectPath(id: existing.id, path: generalURL.path)
                existing.path = generalURL.path
                try await refreshProjects()
                appendLog(.info, "Repointed General project to canonical path \(generalURL.path)")
            }

            try await prepareProjectFolderStructure(projectPath: generalURL.path)
            try await refreshGeneralThreads(generalProjectID: existing.id)
            return
        }

        // Seed AGENTS.md so the runtime understands the context.
        let agentsMD = generalURL.appendingPathComponent("AGENTS.md")
        if !FileManager.default.fileExists(atPath: agentsMD.path) {
            let content = """
            # General

            This project is the default catch-all for conversations that are not tied to a specific codebase or topic.
            Treat threads here like general chat sessions - helpful, conversational, and not bound to any particular repository.
            """
            try content.write(to: agentsMD, atomically: true, encoding: .utf8)
        }

        let project = try await projectRepository.createProject(
            named: "General",
            path: generalURL.path,
            trustState: .trusted,
            isGeneralProject: true
        )
        try await applyGlobalSafetyDefaultsToProjectIfNeeded(projectID: project.id)

        try await prepareProjectFolderStructure(projectPath: project.path)
        try await refreshProjects()
        try await refreshGeneralThreads(generalProjectID: project.id)
        appendLog(.info, "Created General project at \(generalURL.path)")
    }

    func refreshGeneralThreads(generalProjectID: UUID? = nil) async throws {
        guard let threadRepository else { return }
        let projectID = generalProjectID ?? generalProject?.id
        guard let projectID else { return }

        let threads = try await threadRepository.listThreads(projectID: projectID)
        generalThreadsState = .loaded(threads)
    }

    func toggleProjectExpanded(_ projectID: UUID) {
        if expandedProjectIDs.contains(projectID) {
            expandedProjectIDs.remove(projectID)
        } else {
            expandedProjectIDs.insert(projectID)
            // Load threads for this project if not already selected.
            if selectedProjectID != projectID {
                Task {
                    do {
                        selectedProjectID = projectID
                        try await refreshThreads()
                        try await refreshSkills()
                        refreshModsSurface()
                        refreshConversationState()
                    } catch {
                        appendLog(.error, "Failed to load threads for expanded project: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func openSkillsAndMods() {
        detailDestination = .skillsAndMods
        selectedThreadID = nil
        model_refreshSkillsAndMods()
    }

    private func model_refreshSkillsAndMods() {
        Task {
            do {
                try await refreshSkills()
            } catch {
                appendLog(.error, "Failed to refresh skills: \(error.localizedDescription)")
            }
            refreshModsSurface()
        }
    }
}
