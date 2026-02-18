import AppKit
import CodexChatCore
import CodexMemory
import Foundation

extension AppModel {
    func openProjectFolder() {
        guard let projectRepository else { return }

        let panel = NSOpenPanel()
        panel.title = "Open Project Folder"
        panel.prompt = "Open Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let url = panel.url
        else {
            return
        }

        Task {
            do {
                let path = url.standardizedFileURL.path
                if let existing = try await projectRepository.getProject(path: path) {
                    selectedProjectID = existing.id
                    try await prepareProjectFolderStructure(projectPath: existing.path)
                    try await persistSelection()
                    try await refreshThreads()
                    try await ensureSelectedProjectHasDefaultThread()
                    try await refreshSkills()
                    refreshModsSurface()
                    refreshConversationState()
                    projectStatusMessage = "Opened existing project at \(path)."
                    appendLog(.info, "Opened existing project \(existing.name)")
                    return
                }

                let trustState: ProjectTrustState = Self.isGitProject(path: path) ? .trusted : .untrusted
                let project = try await projectRepository.createProject(
                    named: url.lastPathComponent,
                    path: path,
                    trustState: trustState
                )

                try await refreshProjects()
                selectedProjectID = project.id
                try await prepareProjectFolderStructure(projectPath: project.path)
                try await persistSelection()
                try await refreshThreads()
                try await ensureSelectedProjectHasDefaultThread()
                try await refreshSkills()
                refreshModsSurface()
                refreshConversationState()
                projectStatusMessage = trustState == .trusted
                    ? "Project opened and trusted (Git repository detected)."
                    : "Project opened in untrusted mode. Read-only is recommended until you trust this project."
                appendLog(.info, "Opened project \(project.name) at \(path)")
            } catch {
                projectsState = .failed(error.localizedDescription)
                appendLog(.error, "Open project failed: \(error.localizedDescription)")
            }
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

    private func prepareProjectFolderStructure(projectPath: String) async throws {
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

    private func ensureSelectedProjectHasDefaultThread() async throws {
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
        refreshConversationState()
        appendLog(.info, "Created default thread for project \(selectedProjectID.uuidString)")
    }
}
