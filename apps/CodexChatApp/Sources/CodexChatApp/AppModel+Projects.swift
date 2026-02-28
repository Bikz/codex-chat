import AppKit
import CodexChatCore
import CodexMemory
import Foundation

extension AppModel {
    static func clampedNetworkAccess(
        for sandboxMode: ProjectSandboxMode,
        networkAccess: Bool
    ) -> Bool {
        guard sandboxMode == .workspaceWrite else {
            return false
        }
        return networkAccess
    }

    func isProjectSidebarVisuallySelected(_ projectID: UUID) -> Bool {
        guard selectedProjectID == projectID else {
            return false
        }

        guard let selectedThreadID else {
            return true
        }

        if let selectedThread = threads.first(where: { $0.id == selectedThreadID }) {
            return selectedThread.projectId != projectID
        }

        if case let .loaded(generalThreads) = generalThreadsState,
           let selectedThread = generalThreads.first(where: { $0.id == selectedThreadID })
        {
            return selectedThread.projectId != projectID
        }

        return false
    }

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

    func removeSelectedProjectFromCodexChat() {
        guard let selectedProject,
              let projectRepository
        else {
            projectStatusMessage = "Select a project first."
            return
        }

        guard !selectedProject.isGeneralProject else {
            projectStatusMessage = "The General project cannot be removed."
            return
        }

        let removedProject = selectedProject
        let fallbackProjectID = projects.first(where: { $0.id != removedProject.id && $0.isGeneralProject })?.id
            ?? projects.first(where: { $0.id != removedProject.id })?.id

        Task {
            do {
                try await projectRepository.deleteProject(id: removedProject.id)

                expandedProjectIDs.remove(removedProject.id)
                if selectedProjectID == removedProject.id {
                    selectedProjectID = fallbackProjectID
                    selectedThreadID = nil
                    draftChatProjectID = nil
                }

                try await refreshProjects()

                let hasValidSelection = selectedProjectID.map { id in
                    projects.contains { $0.id == id }
                } ?? false
                if !hasValidSelection {
                    selectedProjectID = fallbackProjectID ?? projects.first?.id
                }

                if let selectedProjectID {
                    if generalProject?.id == selectedProjectID {
                        try await refreshGeneralThreads(generalProjectID: selectedProjectID)
                    } else {
                        try await refreshThreads()
                    }
                } else {
                    threadsState = .loaded([])
                    selectedThreadID = nil
                    draftChatProjectID = nil
                    detailDestination = .none
                }

                try await refreshArchivedThreads()
                try await refreshSkills()
                refreshModsSurface()
                refreshConversationState()
                try await persistSelection()

                projectStatusMessage = "Removed \(removedProject.name) from CodexChat. Files remain on disk."
                appendLog(
                    .info,
                    "Disconnected project \(removedProject.name) (\(removedProject.id.uuidString)) from app metadata."
                )
            } catch {
                projectStatusMessage = "Failed to remove project: \(error.localizedDescription)"
                appendLog(.error, "Failed to remove project \(removedProject.id.uuidString): \(error.localizedDescription)")
            }
        }
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

    func updateGeneralProjectSafetySettings(
        sandboxMode: ProjectSandboxMode,
        approvalPolicy: ProjectApprovalPolicy,
        networkAccess: Bool,
        webSearch: ProjectWebSearchMode
    ) {
        guard let projectRepository,
              let generalProjectID = generalProject?.id
        else {
            projectStatusMessage = "General project is unavailable."
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
                    id: generalProjectID,
                    settings: settings
                )
                try await refreshProjects()
                projectStatusMessage = "Updated safety settings for the General project."
            } catch {
                projectStatusMessage = "Failed to update General project safety settings: \(error.localizedDescription)"
                appendLog(.error, "Failed to update General project safety settings: \(error.localizedDescription)")
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

    func updateGeneralProjectMemorySettings(
        writeMode: ProjectMemoryWriteMode,
        embeddingsEnabled: Bool
    ) {
        guard let projectRepository,
              let generalProjectID = generalProject?.id
        else {
            memoryStatusMessage = "General project is unavailable."
            return
        }

        let settings = ProjectMemorySettings(writeMode: writeMode, embeddingsEnabled: embeddingsEnabled)
        Task {
            do {
                _ = try await projectRepository.updateProjectMemorySettings(
                    id: generalProjectID,
                    settings: settings
                )
                try await refreshProjects()
                memoryStatusMessage = "Updated memory settings for the General project."
            } catch {
                memoryStatusMessage = "Failed to update General project memory settings: \(error.localizedDescription)"
                appendLog(.error, "Failed to update General project memory settings: \(error.localizedDescription)")
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

    func trustGeneralProject() {
        setGeneralProjectTrustState(.trusted)
    }

    func untrustGeneralProject() {
        setGeneralProjectTrustState(.untrusted)
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

    private func setGeneralProjectTrustState(_ trustState: ProjectTrustState) {
        guard let projectRepository,
              let generalProjectID = generalProject?.id
        else {
            projectStatusMessage = "General project is unavailable."
            return
        }

        Task {
            do {
                _ = try await projectRepository.updateProjectTrustState(id: generalProjectID, trustState: trustState)
                try await refreshProjects()
                projectStatusMessage = trustState == .trusted
                    ? "General project trusted."
                    : "General project marked untrusted."
            } catch {
                projectStatusMessage = "Failed to update General project trust state: \(error.localizedDescription)"
                appendLog(.error, "Failed to update General project trust state: \(error.localizedDescription)")
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
            at: projectURL.appendingPathComponent("chats/threads", isDirectory: true),
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

    func ensureGeneralDraftChatSelectionIfNeeded() {
        guard selectedThreadID == nil else {
            return
        }
        guard !hasActiveDraftChatForSelectedProject else {
            return
        }
        let targetProjectID = selectedProjectID ?? generalProject?.id
        guard let targetProjectID else {
            return
        }

        beginDraftChat(in: targetProjectID)
        appendLog(.debug, "Activated draft chat fallback because no chat selection was available.")
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
            try ensureGeneralAgentsGuidance(projectURL: generalURL)
            try await ensureGeneralProjectSafetyMigrated(projectID: existing.id)
            try await refreshGeneralThreads(generalProjectID: existing.id)
            return
        }

        // Seed AGENTS.md so the runtime understands the context.
        try ensureGeneralAgentsGuidance(projectURL: generalURL)

        let project = try await projectRepository.createProject(
            named: "General",
            path: generalURL.path,
            trustState: .trusted,
            isGeneralProject: true
        )
        _ = try await projectRepository.updateProjectSafetySettings(
            id: project.id,
            settings: generalProjectSafetyDefaults
        )
        try await preferenceRepository?.setPreference(key: .generalProjectSafetyMigrationV1, value: "1")

        try await prepareProjectFolderStructure(projectPath: project.path)
        try await refreshProjects()
        try await refreshGeneralThreads(generalProjectID: project.id)
        appendLog(.info, "Created General project at \(generalURL.path)")
    }

    func refreshGeneralThreads(generalProjectID: UUID? = nil) async throws {
        guard let threadRepository else {
            generalThreadsState = .failed("Thread repository is unavailable.")
            return
        }
        let projectID = generalProjectID ?? generalProject?.id
        guard let projectID else {
            generalThreadsState = .loaded([])
            return
        }

        generalThreadsState = .loading
        do {
            let threads = try await threadRepository.listThreads(projectID: projectID)
            generalThreadsState = .loaded(threads)
        } catch {
            generalThreadsState = .failed(error.localizedDescription)
            throw error
        }
    }

    func toggleProjectExpanded(_ projectID: UUID) {
        if expandedProjectIDs.contains(projectID) {
            expandedProjectIDs.remove(projectID)
        } else {
            expandedProjectIDs.insert(projectID)
        }
    }

    @discardableResult
    func activateProjectFromSidebar(_ projectID: UUID) -> Bool {
        let isSelectingDifferentProject = selectedProjectID != projectID
        if isSelectingDifferentProject || selectedThreadID == nil {
            selectProject(projectID)
        }
        toggleProjectExpanded(projectID)
        return expandedProjectIDs.contains(projectID)
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
            await refreshSkillsCatalog()
            refreshModsSurface()
        }
    }

    private var generalProjectSafetyDefaults: ProjectSafetySettings {
        ProjectSafetySettings(
            sandboxMode: .readOnly,
            approvalPolicy: .onRequest,
            networkAccess: false,
            webSearch: .cached
        )
    }

    private func ensureGeneralProjectSafetyMigrated(projectID: UUID) async throws {
        guard let projectRepository else { return }

        let migrationApplied = try await preferenceRepository?
            .getPreference(key: .generalProjectSafetyMigrationV1) == "1"
        guard !migrationApplied else {
            return
        }

        _ = try await projectRepository.updateProjectSafetySettings(
            id: projectID,
            settings: generalProjectSafetyDefaults
        )
        try await preferenceRepository?.setPreference(key: .generalProjectSafetyMigrationV1, value: "1")
        try await refreshProjects()
        appendLog(.info, "Migrated General project safety defaults to read-only + on-request.")
    }

    private func ensureGeneralAgentsGuidance(projectURL: URL) throws {
        let agentsURL = projectURL.appendingPathComponent("AGENTS.md", isDirectory: false)
        let guidanceBlock = """
        <!-- CODEXCHAT_HISTORY_GUIDANCE_BEGIN -->
        ## Chat Transcript Files

        Conversation history is stored in `chats/threads/*.md`.
        Read these transcript files when cross-thread context is relevant.
        Treat transcript files as append-only historical records unless the user explicitly asks to edit them.
        <!-- CODEXCHAT_HISTORY_GUIDANCE_END -->
        """

        if !FileManager.default.fileExists(atPath: agentsURL.path) {
            let content = """
            # General

            This project is the default catch-all for conversations that are not tied to a specific codebase or topic.
            Treat threads here like general chat sessions - helpful, conversational, and not bound to any particular repository.

            \(guidanceBlock)
            """
            try content.write(to: agentsURL, atomically: true, encoding: .utf8)
            return
        }

        var content = try String(contentsOf: agentsURL, encoding: .utf8)
        if content.contains("CODEXCHAT_HISTORY_GUIDANCE_BEGIN") {
            return
        }

        if !content.hasSuffix("\n") {
            content += "\n"
        }
        content += "\n\(guidanceBlock)\n"
        try content.write(to: agentsURL, atomically: true, encoding: .utf8)
    }
}
