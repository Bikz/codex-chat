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
                        .frame(width: 200)

                    Divider()
                        .opacity(tokens.surfaces.hairlineOpacity)

                    sessionSurface(projectName: project.name, projectID: project.id, workspace: workspace)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(tokens.materials.panelMaterial.material)
                .clipShape(RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
            } else {
                EmptyStateView(
                    title: "No project selected",
                    message: "Select a project to open Shell Workspace.",
                    systemImage: "terminal"
                )
                .background(tokens.materials.panelMaterial.material)
                .clipShape(RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: tokens.radius.medium, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
            }
        }
    }

    private func sessionsSidebar(workspace: ProjectShellWorkspaceState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: tokens.spacing.xSmall) {
                Label("Shells", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)

                Spacer()

                Button {
                    model.createShellSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Create shell session")
                .help("New shell session")
            }
            .padding(.horizontal, tokens.spacing.small)
            .frame(height: 30)

            Divider()
                .opacity(tokens.surfaces.hairlineOpacity)

            if workspace.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.secondary)

                    Text("No sessions")
                        .font(.caption.weight(.semibold))

                    Text("Create a shell to start working.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Start Session") {
                        model.createShellSession()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(tokens.spacing.medium)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(workspace.sessions) { session in
                            HStack(spacing: 6) {
                                Button {
                                    model.selectShellSession(session.id)
                                } label: {
                                    let isSelected = workspace.selectedSessionID == session.id
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(isSelected ? Color(hex: tokens.palette.accentHex) : Color.secondary.opacity(0.4))
                                            .frame(width: 6, height: 6)

                                        Text(session.name)
                                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                            .lineLimit(1)

                                        Spacer(minLength: 6)

                                        if isSelected {
                                            Text("\(session.rootNode.leafCount())")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(height: 26)
                                    .padding(.horizontal, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Select \(session.name)")

                                Button {
                                    model.closeShellSession(session.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Close \(session.name)")
                                .help("Close session")
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
        .background(Color.primary.opacity(tokens.surfaces.baseOpacity * 0.6))
    }

    @ViewBuilder
    private func sessionSurface(projectName: String, projectID: UUID, workspace: ProjectShellWorkspaceState) -> some View {
        if workspace.sessions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "terminal")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)

                Text("Shell workspace is ready")
                    .font(.subheadline.weight(.semibold))

                Text("Create a session to open a shell.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Start Session") {
                    model.createShellSession()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(tokens.spacing.medium)
        } else if let session = workspace.selectedSession() {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    if let activePane = ShellSplitTree.findLeaf(in: session.rootNode, paneID: session.activePaneID) {
                        Text(ShellPathPresentation.compactPath(activePane.cwd))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(activePane.cwd)
                    } else {
                        Text(projectName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("\(session.rootNode.leafCount()) pane\(session.rootNode.leafCount() == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button {
                        model.createShellSession()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Create shell session")
                    .help("New shell session")
                }
                .padding(.horizontal, tokens.spacing.small)
                .frame(height: 30)
                .background(Color.primary.opacity(tokens.surfaces.baseOpacity * 0.65))

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
