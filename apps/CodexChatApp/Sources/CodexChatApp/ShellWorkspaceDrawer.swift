import CodexChatUI
import SwiftUI

struct ShellWorkspaceDrawer: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let project = model.selectedProject {
                let workspace = model.selectedProjectShellWorkspace
                    ?? ProjectShellWorkspaceState(projectID: project.id)
                HStack(spacing: 0) {
                    sessionsSidebar(workspace: workspace)
                        .frame(width: 48)

                    Divider()
                        .opacity(0.14)

                    sessionSurface(projectID: project.id, workspace: workspace)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(shellSurfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(borderColor)
                )
            } else {
                EmptyStateView(
                    title: "No project selected",
                    message: "Select a project to open Shell Workspace.",
                    systemImage: "terminal"
                )
                .background(shellSurfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(borderColor)
                )
            }
        }
    }

    private func sessionsSidebar(workspace: ProjectShellWorkspaceState) -> some View {
        VStack(spacing: 6) {
            Button {
                model.createShellSession()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(iconBackgroundColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create shell session")
            .help("New shell session")

            Divider()
                .opacity(0.1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(Array(workspace.sessions.enumerated()), id: \.element.id) { index, session in
                        let isSelected = workspace.selectedSessionID == session.id
                        Button {
                            model.selectShellSession(session.id)
                        } label: {
                            Image(systemName: "terminal")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .foregroundStyle(isSelected ? selectedIconColor : .secondary)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? selectedIconBackgroundColor : iconBackgroundColor)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select \(session.name)")
                        .help("Session \(index + 1): \(session.name)")
                        .contextMenu {
                            Button("Close Session") {
                                model.closeShellSession(session.id)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(shellSurfaceColor)
    }

    @ViewBuilder
    private func sessionSurface(projectID: UUID, workspace: ProjectShellWorkspaceState) -> some View {
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
            .padding(16)
        } else if let session = workspace.selectedSession() {
            ShellSplitContainerView(model: model, projectID: projectID, session: session)
                .background(shellSurfaceColor)
        } else {
            EmptyStateView(
                title: "Session unavailable",
                message: "Select a shell session from the left panel.",
                systemImage: "terminal"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var shellSurfaceColor: Color {
        Color(hex: tokens.palette.panelHex)
    }

    private var borderColor: Color {
        Color.primary.opacity(tokens.surfaces.hairlineOpacity * (colorScheme == .dark ? 1.4 : 1.1))
    }

    private var iconBackgroundColor: Color {
        Color.primary.opacity(tokens.surfaces.baseOpacity * 1.2)
    }

    private var selectedIconBackgroundColor: Color {
        Color.primary.opacity(tokens.surfaces.activeOpacity * 1.05)
    }

    private var selectedIconColor: Color {
        Color.primary.opacity(0.92)
    }
}
