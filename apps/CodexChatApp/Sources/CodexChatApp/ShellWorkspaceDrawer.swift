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
                    sessionSurface(projectName: project.name, projectID: project.id, workspace: workspace)
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
        .background(tokens.materials.panelMaterial.material)
    }

    private func sessionsSidebar(workspace: ProjectShellWorkspaceState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Shells")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    model.createShellSession()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("New shell session")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(tokens.materials.cardMaterial.material)

            Divider()

            if workspace.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Starting shell session...")
                        .font(.caption.weight(.semibold))

                    Text("If it does not start, create one manually.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button("Start Session") {
                        model.createShellSession()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(workspace.sessions) { session in
                            HStack(spacing: 6) {
                                Button {
                                    model.selectShellSession(session.id)
                                } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: workspace.selectedSessionID == session.id ? "terminal.fill" : "terminal")
                                            .font(.system(size: 12, weight: .medium))

                                        Text(session.name)
                                            .font(.system(size: 13, weight: workspace.selectedSessionID == session.id ? .semibold : .regular))
                                            .lineLimit(1)

                                        Spacer(minLength: 6)
                                    }
                                    .frame(height: 28)
                                    .padding(.horizontal, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(workspace.selectedSessionID == session.id ? Color.primary.opacity(0.1) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    model.closeShellSession(session.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .semibold))
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
        .background(tokens.materials.cardMaterial.material)
    }

    @ViewBuilder
    private func sessionSurface(projectName: String, projectID: UUID, workspace: ProjectShellWorkspaceState) -> some View {
        if workspace.sessions.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Starting shell...")
                    .font(.subheadline.weight(.semibold))
                Text("No session is active yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Start Session") {
                    model.createShellSession()
                }
                .buttonStyle(.bordered)
            }
        } else if let session = workspace.selectedSession() {
            VStack(spacing: 0) {
                HStack {
                    Text(session.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if let activePane = ShellSplitTree.findLeaf(in: session.rootNode, paneID: session.activePaneID) {
                        Text(activePane.cwd)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(projectName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        model.createShellSession()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help("New shell session")

                    Text("\(session.rootNode.leafCount()) pane(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
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
