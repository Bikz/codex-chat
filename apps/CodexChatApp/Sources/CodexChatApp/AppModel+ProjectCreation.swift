import AppKit
import CodexChatCore
import Foundation

extension AppModel {
    func presentNewProjectSheet() {
        isNewProjectSheetVisible = true
    }

    func closeNewProjectSheet() {
        isNewProjectSheetVisible = false
    }

    @discardableResult
    func addExistingProjectFromPanel() async -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Add Existing Folder or Repository"
        panel.prompt = "Add Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK,
              let url = panel.url
        else {
            return false
        }

        do {
            try await addOrActivateProject(at: url)
            return true
        } catch {
            projectsState = .failed(error.localizedDescription)
            appendLog(.error, "Add existing project failed: \(error.localizedDescription)")
            projectStatusMessage = "Failed to add project: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func createManagedProject(named requestedName: String) async -> Bool {
        guard let projectRepository else {
            return false
        }

        do {
            try storagePaths.ensureRootStructure()
            let destinationURL = storagePaths.uniqueProjectDirectoryURL(requestedName: requestedName)
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

            let project = try await projectRepository.createProject(
                named: destinationURL.lastPathComponent,
                path: destinationURL.path,
                trustState: .untrusted,
                isGeneralProject: false
            )
            try await applyGlobalSafetyDefaultsToProjectIfNeeded(projectID: project.id)

            try await activateProject(project)
            projectStatusMessage = "Created new project at \(destinationURL.path)."
            appendLog(.info, "Created project \(project.name) at \(destinationURL.path)")
            return true
        } catch {
            projectsState = .failed(error.localizedDescription)
            appendLog(.error, "Create project failed: \(error.localizedDescription)")
            projectStatusMessage = "Failed to create project: \(error.localizedDescription)"
            return false
        }
    }

    func openProjectFolder() {
        presentNewProjectSheet()
    }

    func initializeGitForSelectedProject() {
        guard let project = selectedProject else {
            projectStatusMessage = "Select a project first."
            return
        }

        guard !Self.isGitProject(path: project.path) else {
            projectStatusMessage = "Git is already initialized for this project."
            return
        }

        Task {
            do {
                try Self.runGitInit(projectPath: project.path)
                projectStatusMessage = "Initialized Git repository at \(project.path)."
                try await refreshProjects()
            } catch {
                projectStatusMessage = "Failed to initialize Git repository: \(error.localizedDescription)"
                appendLog(.error, "Git init failed for \(project.path): \(error.localizedDescription)")
            }
        }
    }

    private static func runGitInit(projectPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "init", projectPath]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "git init exited with status \(process.terminationStatus)"
            throw NSError(
                domain: "CodexChatApp.ProjectGitInit",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: detail]
            )
        }
    }

    private func addOrActivateProject(at url: URL) async throws {
        guard let projectRepository else { return }

        let path = url.standardizedFileURL.path
        if let existing = try await projectRepository.getProject(path: path) {
            try await activateProject(existing)
            projectStatusMessage = "Opened existing project at \(path)."
            appendLog(.info, "Opened existing project \(existing.name)")
            return
        }

        let trustState: ProjectTrustState = Self.isGitProject(path: path) ? .trusted : .untrusted
        let project = try await projectRepository.createProject(
            named: url.lastPathComponent,
            path: path,
            trustState: trustState,
            isGeneralProject: false
        )
        try await applyGlobalSafetyDefaultsToProjectIfNeeded(projectID: project.id)

        try await activateProject(project)
        projectStatusMessage = trustState == .trusted
            ? "Project added and trusted (Git repository detected)."
            : "Project added in untrusted mode. Read-only is recommended until you trust this project."
        appendLog(.info, "Added project \(project.name) at \(path)")
    }

    private func activateProject(_ project: ProjectRecord) async throws {
        let transitionGeneration = beginSelectionTransition()
        let span = await PerformanceTracer.shared.begin(
            name: "thread.activateProject",
            metadata: ["projectID": project.id.uuidString]
        )
        defer {
            Task {
                await PerformanceTracer.shared.end(span)
            }
            finishSelectionTransition(transitionGeneration)
        }

        let previousProjectID = selectedProjectID
        try await refreshProjects()
        guard isCurrentSelectionTransition(transitionGeneration) else { return }
        selectedProjectID = project.id
        selectedThreadID = nil
        refreshConversationState()
        try await prepareProjectFolderStructure(projectPath: project.path)
        guard isCurrentSelectionTransition(transitionGeneration) else { return }
        try await persistSelection()
        guard isCurrentSelectionTransition(transitionGeneration) else { return }
        try await refreshThreads(refreshSelectedThreadFollowUpQueue: false)
        let hydratedThreadID = selectedThreadID
        guard isCurrentSelectionTransition(transitionGeneration) else { return }
        if let hydratedThreadID {
            scheduleSelectedThreadHydration(
                threadID: hydratedThreadID,
                transitionGeneration: transitionGeneration,
                reason: "activateProject"
            )
        }
        guard isCurrentSelectionTransition(transitionGeneration) else { return }
        refreshConversationStateIfSelectedThreadChanged(hydratedThreadID)
        scheduleProjectSecondarySurfaceRefresh(
            transitionGeneration: transitionGeneration,
            targetProjectID: project.id,
            projectContextChanged: previousProjectID != project.id,
            reason: "activateProject"
        )
    }
}
