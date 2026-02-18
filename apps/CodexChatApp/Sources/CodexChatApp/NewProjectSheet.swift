import CodexChatUI
import SwiftUI

struct NewProjectSheet: View {
    @ObservedObject var model: AppModel
    @State private var projectName = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project")
                .font(.title3.weight(.semibold))

            Text("Create a project under your CodexChat root, or add an existing folder/repository in place.")
                .font(.callout)
                .foregroundStyle(.secondary)

            createSection
            addExistingSection

            if isBusy {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let status = model.projectStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Close") {
                    model.closeNewProjectSheet()
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
        .padding(20)
        .frame(minWidth: 580, minHeight: 360)
    }

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create New Project")
                .font(.headline)

            TextField("Project name", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .disabled(isBusy)

            Text(previewPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Button {
                Task {
                    await createProject()
                }
            } label: {
                Label("Create Project", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: tokens.palette.accentHex))
            .disabled(isBusy)
        }
        .padding(12)
        .tokenCard(style: .card, radius: 12, strokeOpacity: 0.08)
    }

    private var addExistingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Existing Folder or Repository")
                .font(.headline)

            Text("Use this to register an existing local folder or Git repository without moving it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await addExistingProject()
                }
            } label: {
                Label("Choose Existing Folder…", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)
        }
        .padding(12)
        .tokenCard(style: .card, radius: 12, strokeOpacity: 0.08)
    }

    private var previewPath: String {
        let destination = model.storagePaths.uniqueProjectDirectoryURL(requestedName: projectName)
        return destination.path
    }

    @MainActor
    private func createProject() async {
        isBusy = true
        errorMessage = nil
        let created = await model.createManagedProject(named: projectName)
        isBusy = false

        if created {
            model.closeNewProjectSheet()
            return
        }

        errorMessage = model.projectStatusMessage ?? "Failed to create project."
    }

    @MainActor
    private func addExistingProject() async {
        isBusy = true
        errorMessage = nil
        let added = await model.addExistingProjectFromPanel()
        isBusy = false

        if added {
            model.closeNewProjectSheet()
            return
        }

        if errorMessage == nil {
            errorMessage = model.projectStatusMessage
        }
    }
}
