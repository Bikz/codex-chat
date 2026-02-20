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

    var body: some View {
        SkillsModsCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                header

                Text(item.skill.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                badgeRow
                targetPicker
                enabledSummary
                metadata
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
            }

            Spacer()

            Button(SkillsModsPresentation.updateActionLabel(for: item.updateCapability)) {
                onUpdate()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(item.updateCapability == .unavailable)
            .help(SkillsModsPresentation.updateActionHelp(for: item.updateCapability))
            .accessibilityLabel("\(SkillsModsPresentation.updateActionLabel(for: item.updateCapability)) \(item.skill.name)")
        }
    }

    private var badgeRow: some View {
        HStack(spacing: 6) {
            Text("Installed")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))

            Text(item.skill.scope.rawValue.capitalized)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))

            if item.skill.hasScripts {
                Label("Scripts", systemImage: "terminal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
            }

            Spacer(minLength: 0)
        }
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Enable target")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                targetButton(.global, title: "Global")
                targetButton(.general, title: "General")
                targetButton(.project, title: "Project", isDisabled: !hasSelectedProject)
            }
        }
    }

    private func targetButton(
        _ target: SkillEnablementTarget,
        title: String,
        isDisabled: Bool = false
    ) -> some View {
        let isSelected = selectedEnablementTarget == target

        return Button(title) {
            onEnablementTargetChanged(target)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : Color.primary.opacity(0.06)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.accentColor.opacity(0.55)
                        : Color.primary.opacity(0.12)
                )
        )
        .opacity(isDisabled ? 0.55 : 1)
        .disabled(isDisabled)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var enabledSummary: some View {
        Text(SkillsModsPresentation.enabledTargetsSummary(for: item, hasSelectedProject: hasSelectedProject))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.skill.skillPath)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Use in next message") {
                onInsert()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!item.isEnabledForSelectedProject)

            Button {
                onToggle(!isEnabledForSelectedTarget)
            } label: {
                Label(isEnabledForSelectedTarget ? "Disable" : "Enable", systemImage: isEnabledForSelectedTarget ? "xmark.circle" : "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canToggleSelectedTarget)

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
                        installer: installer
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
