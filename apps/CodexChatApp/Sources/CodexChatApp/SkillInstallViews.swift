import CodexChatCore
import CodexChatUI
import CodexSkills
import SwiftUI

struct SkillRow: View {
    let item: AppModel.SkillListItem
    let hasSelectedProject: Bool
    let onToggle: (Bool) -> Void
    let onInsert: () -> Void
    let onUpdate: () -> Void

    var body: some View {
        SkillsModsCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                header

                Text(item.skill.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

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
                HStack(spacing: 8) {
                    Text(item.skill.name)
                        .font(.headline)
                        .lineLimit(1)

                    Text(item.skill.scope.rawValue.capitalized)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                }
            }

            Spacer()

            Button {
                onUpdate()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Update skill")
            .accessibilityLabel("Update \(item.skill.name)")
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            if item.skill.hasScripts {
                Label("Scripts detected", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

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
            Button {
                onToggle(!item.isEnabledForProject)
            } label: {
                Label(
                    item.isEnabledForProject ? "Enabled" : "Enable",
                    systemImage: item.isEnabledForProject ? "checkmark.circle.fill" : "circle"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!hasSelectedProject)

            Button("Use in Composer") {
                onInsert()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!item.isEnabledForProject)

            Spacer()
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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Install Skill")
                .font(.title3.weight(.semibold))

            Text("Install from a git source or run the optional npx installer. Project installs go to `.agents/skills`.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("https://github.com/org/skill-repo.git", text: $source)
                .textFieldStyle(.roundedBorder)

            Picker("Scope", selection: $scope) {
                Text("Project").tag(SkillInstallScope.project)
                Text("Global").tag(SkillInstallScope.global)
            }
            .pickerStyle(.segmented)

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
