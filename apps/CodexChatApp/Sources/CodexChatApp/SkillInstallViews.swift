import CodexChatCore
import CodexChatUI
import CodexSkills
import SwiftUI

struct SkillRow: View {
    let item: AppModel.SkillListItem
    let hasSelectedProject: Bool
    let onInsert: () -> Void
    let onUpdate: () -> Void
    let onRemoveFromProject: () -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void

    var body: some View {
        SkillsModsCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                header

                Text(item.skill.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if item.skill.hasScripts {
                    Label("Includes scripts", systemImage: "terminal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                actions
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(hex: "#F39C31").opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "cube.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(hex: "#CC7E1F"))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.skill.name)
                    .font(.headline)
                    .lineLimit(1)

                Text("Installed · \(item.installScopeSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Use in next message") {
                onInsert()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!item.isEnabledForSelectedProject)

            if hasSelectedProject, item.isEnabledForSelectedProject {
                Button("Remove from this project") {
                    onRemoveFromProject()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Remove") {
                onRemove()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Menu {
                Button(SkillsModsPresentation.updateActionLabel(for: item.updateCapability)) {
                    onUpdate()
                }
                .disabled(item.updateCapability == .unavailable)

                Button("Reveal in Finder") {
                    onReveal()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help(SkillsModsPresentation.updateActionHelp(for: item.updateCapability))
            .accessibilityLabel("More actions for \(item.skill.name)")

            Spacer()
        }
    }
}

struct CatalogSkillRow: View {
    let listing: CatalogSkillListing
    let canInstallToSelectedProjects: Bool
    let onInstallAllProjects: () -> Void
    let onInstallSelectedProjects: () -> Void

    var body: some View {
        SkillsModsCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: "#3B82F6").opacity(0.18))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "shippingbox.fill")
                                .font(.caption2)
                                .foregroundStyle(Color(hex: "#2563EB"))
                        )

                    Text(listing.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Menu {
                        Button("Install to All projects", action: onInstallAllProjects)
                        Button("Install to Selected projects…", action: onInstallSelectedProjects)
                            .disabled(!canInstallToSelectedProjects)
                    } label: {
                        Label("Install", systemImage: "square.and.arrow.down")
                    }
                    .menuStyle(.borderlessButton)
                }

                if let summary = listing.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let source = listing.installSource ?? listing.repositoryURL {
                    Text(source)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct SkillInstallProjectSelectionSheet: View {
    let listing: CatalogSkillListing
    let projects: [ProjectRecord]
    let initiallySelectedProjectIDs: Set<UUID>
    let onCancel: () -> Void
    let onInstall: ([UUID]) -> Void

    @State private var query = ""
    @State private var selectedProjectIDs: Set<UUID> = []

    private var filteredProjects: [ProjectRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return projects
        }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(trimmed)
                || project.path.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Install to Selected projects")
                .font(.title3.weight(.semibold))

            Text(listing.name)
                .font(.headline)

            SkillsModsSearchField(text: $query, placeholder: "Search projects")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredProjects) { project in
                        Toggle(isOn: binding(for: project.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.subheadline.weight(.medium))
                                Text(project.path)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 300)

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)

                Button("Install") {
                    onInstall(Array(selectedProjectIDs))
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProjectIDs.isEmpty)
            }
        }
        .padding(22)
        .frame(minWidth: 560)
        .onAppear {
            selectedProjectIDs = initiallySelectedProjectIDs
        }
    }

    private func binding(for projectID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedProjectIDs.contains(projectID) },
            set: { isSelected in
                if isSelected {
                    selectedProjectIDs.insert(projectID)
                } else {
                    selectedProjectIDs.remove(projectID)
                }
            }
        )
    }
}

struct InstallSkillSheet: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool

    @State private var source = ""
    @State private var pinnedRef = ""
    @State private var scope: SkillInstallScope = .global
    @State private var installer: SkillInstallerKind = .git
    @State private var trustConfirmed = false

    private var isTrustedSource: Bool {
        model.isTrustedSkillSource(source)
    }

    private var canSubmit: Bool {
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (isTrustedSource || trustConfirmed)
            && (scope == .global || model.selectedProject != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Install Skill")
                .font(.title3.weight(.semibold))

            Text("Installing adds skill files to the shared library and links them to all projects or selected projects.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("https://github.com/org/skill-repo.git", text: $source)
                .textFieldStyle(.roundedBorder)

            TextField("Optional git pin (branch/tag/commit)", text: $pinnedRef)
                .textFieldStyle(.roundedBorder)
                .disabled(installer != .git)

            Picker("Scope", selection: $scope) {
                Text("All projects").tag(SkillInstallScope.global)
                Text("Selected project").tag(SkillInstallScope.project)
            }
            .pickerStyle(.segmented)

            if scope == .project, model.selectedProject == nil {
                Text("Select a project before installing to selected projects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Installer", selection: $installer) {
                Text("Git Clone").tag(SkillInstallerKind.git)
                if model.isNodeSkillInstallerAvailable {
                    Text("npx skills add").tag(SkillInstallerKind.npx)
                }
            }
            .pickerStyle(.segmented)

            if !isTrustedSource {
                Toggle("I trust this source and want to install it anyway.", isOn: $trustConfirmed)
                    .toggleStyle(.switch)

                Text("Unknown source detected. Installing may run unreviewed scripts.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let status = model.skillStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }

                Button("Install") {
                    model.installSkill(
                        source: source,
                        scope: scope,
                        installer: installer,
                        allowUntrustedSource: !isTrustedSource && trustConfirmed,
                        pinnedRef: installer == .git ? pinnedRef.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || model.isSkillOperationInProgress)
            }
        }
        .padding(22)
        .frame(minWidth: 560)
        .onChange(of: source) { _, _ in
            trustConfirmed = false
        }
    }
}
