import CodexChatCore
import Foundation

struct UntrustedShellWarningContext: Identifiable, Hashable {
    let projectID: UUID
    let projectName: String

    var id: UUID {
        projectID
    }
}

enum UntrustedShellAcknowledgementsCodec {
    static func decode(_ raw: String?) -> Set<UUID> {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    static func encode(_ values: Set<UUID>) -> String {
        let identifiers = values.map(\.uuidString).sorted()
        guard let data = try? JSONEncoder().encode(identifiers),
              let raw = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return raw
    }
}

extension AppModel {
    var selectedProjectShellWorkspace: ProjectShellWorkspaceState? {
        guard let selectedProjectID else { return nil }
        return shellWorkspacesByProjectID[selectedProjectID]
    }

    var selectedShellSession: ShellSessionState? {
        selectedProjectShellWorkspace?.selectedSession()
    }

    func toggleShellWorkspace() {
        if isShellWorkspaceVisible {
            isShellWorkspaceVisible = false
            return
        }

        Task {
            await openShellWorkspace()
        }
    }

    func createShellSession() {
        guard let project = selectedProject else {
            projectStatusMessage = "Select a project before creating a shell session."
            return
        }

        ensureWorkspaceExists(for: project.id)
        mutateWorkspace(projectID: project.id) { workspace in
            let session = makeShellSession(
                name: nextShellSessionName(in: workspace),
                cwd: project.path
            )
            workspace.sessions.append(session)
            workspace.selectedSessionID = session.id
        }
        isShellWorkspaceVisible = true
    }

    func selectShellSession(_ sessionID: UUID) {
        guard let projectID = selectedProjectID else { return }
        mutateWorkspace(projectID: projectID) { workspace in
            guard workspace.sessions.contains(where: { $0.id == sessionID }) else { return }
            workspace.selectedSessionID = sessionID
        }
    }

    func closeShellSession(_ sessionID: UUID) {
        guard let projectID = selectedProjectID else { return }
        mutateWorkspace(projectID: projectID) { workspace in
            workspace.sessions.removeAll(where: { $0.id == sessionID })
            if workspace.selectedSessionID == sessionID {
                workspace.selectedSessionID = workspace.sessions.first?.id
            }
        }
    }

    func splitShellPane(sessionID: UUID, paneID: UUID, axis: ShellSplitAxis) {
        guard let projectID = selectedProjectID else { return }
        mutateSession(projectID: projectID, sessionID: sessionID) { session in
            guard let current = ShellSplitTree.findLeaf(in: session.rootNode, paneID: paneID) else {
                return
            }
            let newPane = makeShellPane(cwd: current.cwd)
            guard ShellSplitTree.splitLeaf(
                in: &session.rootNode,
                paneID: paneID,
                axis: axis,
                newPane: newPane
            ) else {
                return
            }

            session.activePaneID = newPane.id
            session.updatedAt = Date()
        }
    }

    func closeShellPane(sessionID: UUID, paneID: UUID) {
        guard let projectID = selectedProjectID else { return }

        mutateWorkspace(projectID: projectID) { workspace in
            guard let index = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else {
                return
            }

            var session = workspace.sessions[index]
            let result = ShellSplitTree.closeLeaf(in: session.rootNode, paneID: paneID)
            guard result.didClose else {
                return
            }

            guard let newRoot = result.root else {
                workspace.sessions.remove(at: index)
                if workspace.selectedSessionID == sessionID {
                    workspace.selectedSessionID = workspace.sessions.first?.id
                }
                return
            }

            session.rootNode = newRoot
            if session.activePaneID == paneID {
                session.activePaneID = newRoot.firstLeafID() ?? session.activePaneID
            }
            session.updatedAt = Date()
            workspace.sessions[index] = session
        }
    }

    func focusShellPane(sessionID: UUID, paneID: UUID) {
        guard let projectID = selectedProjectID else { return }

        mutateWorkspace(projectID: projectID) { workspace in
            guard let index = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else {
                return
            }

            var session = workspace.sessions[index]
            guard ShellSplitTree.findLeaf(in: session.rootNode, paneID: paneID) != nil else {
                return
            }

            workspace.selectedSessionID = sessionID
            session.activePaneID = paneID
            session.updatedAt = Date()
            workspace.sessions[index] = session
        }
    }

    func restartShellPane(sessionID: UUID, paneID: UUID) {
        guard let projectID = selectedProjectID else { return }
        mutateSession(projectID: projectID, sessionID: sessionID) { session in
            guard ShellSplitTree.updateLeaf(in: &session.rootNode, paneID: paneID, mutate: { pane in
                pane.processStatus = .running
                pane.lastExitCode = nil
                pane.launchGeneration += 1
                pane.title = "Shell"
            }) else {
                return
            }

            session.activePaneID = paneID
            session.updatedAt = Date()
        }
    }

    func updateShellPaneTitle(projectID: UUID, sessionID: UUID, paneID: UUID, title: String) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        mutateSession(projectID: projectID, sessionID: sessionID) { session in
            var didChange = false
            _ = ShellSplitTree.updateLeaf(in: &session.rootNode, paneID: paneID) { pane in
                guard pane.title != normalized else { return }
                pane.title = normalized
                didChange = true
            }
            if didChange {
                session.updatedAt = Date()
            }
        }
    }

    func updateShellPaneCWD(projectID: UUID, sessionID: UUID, paneID: UUID, cwd: String) {
        let normalized = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        mutateSession(projectID: projectID, sessionID: sessionID) { session in
            var didChange = false
            _ = ShellSplitTree.updateLeaf(in: &session.rootNode, paneID: paneID) { pane in
                guard pane.cwd != normalized else { return }
                pane.cwd = normalized
                didChange = true
            }
            if didChange {
                session.updatedAt = Date()
            }
        }
    }

    func markShellPaneProcessTerminated(projectID: UUID, sessionID: UUID, paneID: UUID, exitCode: Int32?) {
        mutateSession(projectID: projectID, sessionID: sessionID) { session in
            var didChange = false
            _ = ShellSplitTree.updateLeaf(in: &session.rootNode, paneID: paneID) { pane in
                if pane.processStatus != .exited {
                    pane.processStatus = .exited
                    didChange = true
                }
                if pane.lastExitCode != exitCode {
                    pane.lastExitCode = exitCode
                    didChange = true
                }
            }
            if didChange {
                session.updatedAt = Date()
            }
        }
    }

    func confirmUntrustedShellWarning() {
        guard let warning = activeUntrustedShellWarning else { return }
        activeUntrustedShellWarning = nil

        Task { [weak self] in
            guard let self else { return }
            await loadUntrustedShellAcknowledgementsIfNeeded()
            untrustedShellAcknowledgedProjectIDs.insert(warning.projectID)
            await persistUntrustedShellAcknowledgements()
            await openShellWorkspace(forceProjectID: warning.projectID)
        }
    }

    func dismissUntrustedShellWarning() {
        activeUntrustedShellWarning = nil
        isShellWorkspaceVisible = false
    }

    private func openShellWorkspace(forceProjectID: UUID? = nil) async {
        await loadUntrustedShellAcknowledgementsIfNeeded()

        let project: ProjectRecord? = if let forceProjectID {
            projects.first(where: { $0.id == forceProjectID })
        } else {
            selectedProject
        }

        guard let project else {
            projectStatusMessage = "Select a project to open Shell Workspace."
            return
        }

        if project.trustState == .untrusted,
           !untrustedShellAcknowledgedProjectIDs.contains(project.id)
        {
            activeUntrustedShellWarning = UntrustedShellWarningContext(
                projectID: project.id,
                projectName: project.name
            )
            return
        }

        ensureWorkspaceExists(for: project.id)
        ensureWorkspaceHasActiveSession(for: project)
        isShellWorkspaceVisible = true
    }

    private func makeShellSession(name: String, cwd: String) -> ShellSessionState {
        let firstPane = makeShellPane(cwd: cwd)
        return ShellSessionState(
            name: name,
            rootNode: .leaf(firstPane),
            activePaneID: firstPane.id
        )
    }

    private func makeShellPane(cwd: String) -> ShellPaneState {
        ShellPaneState(cwd: cwd, processStatus: .running)
    }

    private func ensureWorkspaceExists(for projectID: UUID) {
        if shellWorkspacesByProjectID[projectID] == nil {
            shellWorkspacesByProjectID[projectID] = ProjectShellWorkspaceState(
                projectID: projectID,
                sessions: [],
                selectedSessionID: nil
            )
        }
    }

    private func ensureWorkspaceHasActiveSession(for project: ProjectRecord) {
        mutateWorkspace(projectID: project.id) { workspace in
            if workspace.sessions.isEmpty {
                let session = makeShellSession(
                    name: nextShellSessionName(in: workspace),
                    cwd: project.path
                )
                workspace.sessions = [session]
                workspace.selectedSessionID = session.id
                return
            }

            if workspace.selectedSessionID == nil {
                workspace.selectedSessionID = workspace.sessions.first?.id
            }
        }
    }

    private func mutateWorkspace(projectID: UUID, mutate: (inout ProjectShellWorkspaceState) -> Void) {
        var workspace = shellWorkspacesByProjectID[projectID] ?? ProjectShellWorkspaceState(projectID: projectID)
        mutate(&workspace)
        shellWorkspacesByProjectID[projectID] = workspace
    }

    private func mutateSession(
        projectID: UUID,
        sessionID: UUID,
        mutate: (inout ShellSessionState) -> Void
    ) {
        mutateWorkspace(projectID: projectID) { workspace in
            guard let sessionIndex = workspace.sessions.firstIndex(where: { $0.id == sessionID }) else {
                return
            }

            var session = workspace.sessions[sessionIndex]
            mutate(&session)
            workspace.sessions[sessionIndex] = session

            if workspace.selectedSessionID == nil {
                workspace.selectedSessionID = sessionID
            }
        }
    }

    private func nextShellSessionName(in workspace: ProjectShellWorkspaceState) -> String {
        let prefix = "Shell "
        let maxIndex = workspace.sessions.compactMap { session in
            guard session.name.hasPrefix(prefix) else { return nil }
            return Int(session.name.dropFirst(prefix.count))
        }.max() ?? 0

        return "Shell \(maxIndex + 1)"
    }

    private func loadUntrustedShellAcknowledgementsIfNeeded() async {
        guard !didLoadUntrustedShellAcknowledgements else { return }
        didLoadUntrustedShellAcknowledgements = true

        guard let preferenceRepository else { return }

        do {
            let raw = try await preferenceRepository.getPreference(key: .untrustedShellAcknowledgements)
            untrustedShellAcknowledgedProjectIDs = UntrustedShellAcknowledgementsCodec.decode(raw)
        } catch {
            appendLog(.warning, "Failed loading shell warning acknowledgements: \(error.localizedDescription)")
        }
    }

    private func persistUntrustedShellAcknowledgements() async {
        guard let preferenceRepository else { return }

        let raw = UntrustedShellAcknowledgementsCodec.encode(untrustedShellAcknowledgedProjectIDs)
        do {
            try await preferenceRepository.setPreference(
                key: .untrustedShellAcknowledgements,
                value: raw
            )
        } catch {
            appendLog(.warning, "Failed saving shell warning acknowledgements: \(error.localizedDescription)")
        }
    }
}
