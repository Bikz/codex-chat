import CodexChatUI
import SwiftUI

struct ShellWorkspaceDrawer: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens

    var body: some View {
        Group {
            if let project = model.selectedProject {
                let workspace = model.selectedProjectShellWorkspace
                    ?? ProjectShellWorkspaceState(projectID: project.id)
                HStack(spacing: 0) {
                    sessionsSidebar(workspace: workspace)
                        .frame(width: 220)
                    Divider()
                    sessionSurface(projectID: project.id, workspace: workspace)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                EmptyStateView(
                    title: "No project selected",
                    message: "Select a project to open Shell Workspace.",
                    systemImage: "terminal"
                )
            }
        }
    }

    private func sessionsSidebar(workspace: ProjectShellWorkspaceState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shell Workspace")
                    .font(.headline)
                Spacer()
                Button {
                    model.createShellSession()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New shell session")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Divider()

            if workspace.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No sessions")
                        .font(.subheadline.weight(.semibold))
                    Text("Create a session to run commands in this project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("New Session") {
                        model.createShellSession()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(workspace.sessions) { session in
                            HStack(spacing: 6) {
                                Button {
                                    model.selectShellSession(session.id)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: workspace.selectedSessionID == session.id ? "terminal.fill" : "terminal")
                                        Text(session.name)
                                            .lineLimit(1)
                                        Spacer(minLength: 6)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(workspace.selectedSessionID == session.id ? Color(hex: tokens.palette.accentHex).opacity(0.12) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    model.closeShellSession(session.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.borderless)
                                .help("Close session")
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(tokens.materials.panelMaterial.material)
    }

    @ViewBuilder
    private func sessionSurface(projectID: UUID, workspace: ProjectShellWorkspaceState) -> some View {
        if workspace.sessions.isEmpty {
            VStack(spacing: 10) {
                EmptyStateView(
                    title: "No shell sessions",
                    message: "Create a session to start an interactive shell in this project.",
                    systemImage: "terminal"
                )

                Button("New Session") {
                    model.createShellSession()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let session = workspace.selectedSession() {
            VStack(spacing: 0) {
                HStack {
                    Text(session.name)
                        .font(.headline)
                    Spacer()
                    Text("\(session.rootNode.leafCount()) pane(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(tokens.materials.cardMaterial.material)

                Divider()

                ShellSplitContainerView(model: model, projectID: projectID, session: session)
            }
        } else {
            EmptyStateView(
                title: "Session unavailable",
                message: "Select a shell session from the left panel.",
                systemImage: "terminal"
            )
        }
    }
}
