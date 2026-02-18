import CodexChatCore
import CodexSkills
import SwiftUI

struct SkillRow: View {
    let item: AppModel.SkillListItem
    let hasSelectedProject: Bool
    let onToggle: (Bool) -> Void
    let onInsert: () -> Void
    let onUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.skill.name)
                    .font(.headline)
                Spacer()
                Text(item.skill.scope.rawValue.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
            }

            Text(item.skill.description)
                .font(.callout)
                .foregroundStyle(.secondary)

            if item.skill.hasScripts {
                Label("Risk: scripts/ detected", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(item.skill.skillPath)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)

            HStack {
                Toggle("Enabled for project", isOn: Binding(
                    get: { item.isEnabledForProject },
                    set: { onToggle($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!hasSelectedProject)

                Spacer()

                Button("Use in Composer") {
                    onInsert()
                }
                .buttonStyle(.bordered)
                .disabled(!item.isEnabledForProject)

                Button("Update") {
                    onUpdate()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
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
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(20)
        .frame(minWidth: 560)
        .onChange(of: source) { _ in
            trustConfirmed = false
        }
    }
}
