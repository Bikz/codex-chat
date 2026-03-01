import CodexChatCore
import CodexChatUI
import CodexSkills
import SwiftUI

struct SkillRow: View {
    let item: AppModel.SkillListItem
    let hasSelectedProject: Bool
    let selectedEnablementTarget: SkillEnablementTarget
    let onEnablementTargetChanged: (SkillEnablementTarget) -> Void
    let onToggle: (Bool) -> Void
    let onInsert: () -> Void
    let onUpdate: () -> Void

    private var isEnabledForSelectedTarget: Bool {
        switch selectedEnablementTarget {
        case .global:
            item.isEnabledGlobally
        case .general:
            item.isEnabledForGeneral
        case .project:
            item.isEnabledForProjectTarget
        }
    }

    private var canToggleSelectedTarget: Bool {
        selectedEnablementTarget != .project || hasSelectedProject
    }

    private var enablementTargetBinding: Binding<SkillEnablementTarget> {
        Binding(
            get: { selectedEnablementTarget },
            set: { onEnablementTargetChanged($0) }
        )
    }

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

                targetPicker
                enabledSummary
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

                Text("Installed · \(item.skill.scope.rawValue.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Enable in")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Enable target", selection: enablementTargetBinding) {
                Text("Global").tag(SkillEnablementTarget.global)
                Text("General").tag(SkillEnablementTarget.general)
                Text("Project").tag(SkillEnablementTarget.project)
                    .disabled(!hasSelectedProject)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if selectedEnablementTarget == .project, !hasSelectedProject {
                Text("Select a project to enable this skill for Project.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var enabledSummary: some View {
        Text(SkillsModsPresentation.enabledTargetsSummary(for: item, hasSelectedProject: hasSelectedProject))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if isEnabledForSelectedTarget {
                Button {
                    onToggle(false)
                } label: {
                    Label("Disable", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canToggleSelectedTarget)
            } else {
                Button {
                    onToggle(true)
                } label: {
                    Label("Enable", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canToggleSelectedTarget)
            }

            Button("Use in next message") {
                onInsert()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!item.isEnabledForSelectedProject)

            Menu {
                Button(SkillsModsPresentation.updateActionLabel(for: item.updateCapability)) {
                    onUpdate()
                }
                .disabled(item.updateCapability == .unavailable)
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
    let canInstallToProject: Bool
    let onInstallProject: () -> Void
    let onInstallGlobal: () -> Void

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
                        Button("Install to Project", action: onInstallProject)
                            .disabled(!canInstallToProject)
                        Button("Install Globally", action: onInstallGlobal)
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

struct InstallSkillSheet: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool

    @State private var source = ""
    @State private var pinnedRef = ""
    @State private var scope: SkillInstallScope = .project
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

            Text("Installing adds skill files. Enabling controls where a skill is active: Global, General, or Project.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("https://github.com/org/skill-repo.git", text: $source)
                .textFieldStyle(.roundedBorder)

            TextField("Optional git pin (branch/tag/commit)", text: $pinnedRef)
                .textFieldStyle(.roundedBorder)
                .disabled(installer != .git)

            Picker("Scope", selection: $scope) {
                Text("Project").tag(SkillInstallScope.project)
                Text("Global").tag(SkillInstallScope.global)
            }
            .pickerStyle(.segmented)

            if scope == .project, model.selectedProject == nil {
                Text("Select a project to install a project-scoped skill.")
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
