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
                VStack(alignment: .leading, spacing: tokens.spacing.small) {
                    workspaceHeader(projectName: project.name, workspace: workspace)

                    HStack(spacing: tokens.spacing.small) {
                        sessionsSidebar(workspace: workspace)
                            .frame(width: 240, maxHeight: .infinity)
                            .tokenCard(style: .card, radius: tokens.radius.small, strokeOpacity: 0.08)

                        sessionSurface(projectName: project.name, projectID: project.id, workspace: workspace)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tokenCard(style: .card, radius: tokens.radius.small, strokeOpacity: 0.08)
                    }
                }
                .padding(tokens.spacing.small)
                .tokenCard(style: .panel, radius: tokens.radius.medium, strokeOpacity: 0.08)
            } else {
                EmptyStateView(
                    title: "No project selected",
                    message: "Select a project to open Shell Workspace.",
                    systemImage: "terminal"
                )
                .tokenCard(style: .panel, radius: tokens.radius.medium, strokeOpacity: 0.08)
            }
        }
    }

    private func workspaceHeader(projectName: String, workspace: ProjectShellWorkspaceState) -> some View {
        HStack(spacing: 10) {
            Label("Shell Workspace", systemImage: "terminal")
                .font(.subheadline.weight(.semibold))

            Text(projectName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text("\(workspace.sessions.count) session\(workspace.sessions.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                model.createShellSession()
            } label: {
                Label("New Session", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("New shell session")
        }
        .padding(.horizontal, 2)
    }

    private func sessionsSidebar(workspace: ProjectShellWorkspaceState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Shells")
                    .font(.subheadline.weight(.semibold))
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
            .padding(.horizontal, tokens.spacing.small)
            .frame(height: 36)

            Divider()
                .opacity(tokens.surfaces.hairlineOpacity)

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
                .padding(tokens.spacing.small)
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
                                    .frame(height: 30)
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
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("Close session")
                            }
                        }
                    }
                    .padding(tokens.spacing.small)
                }
            }
        }
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
                HStack(spacing: 10) {
                    Text(session.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if let activePane = ShellSplitTree.findLeaf(in: session.rootNode, paneID: session.activePaneID) {
                        Text(activePane.cwd)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
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
                .padding(.horizontal, tokens.spacing.small)
                .frame(height: 36)
                .background(Color.primary.opacity(tokens.surfaces.baseOpacity))

                Divider()
                    .opacity(tokens.surfaces.hairlineOpacity)

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
