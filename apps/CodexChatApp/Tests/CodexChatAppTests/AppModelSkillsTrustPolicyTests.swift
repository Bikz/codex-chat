import CodexChatCore
@testable import CodexChatShared
import CodexSkills
import XCTest

@MainActor
final class AppModelSkillsTrustPolicyTests: XCTestCase {
    func testBlockedCapabilitiesForProjectGitInstallInUntrustedProjectIncludesNetworkForRemoteSource() {
        let model = makeModelWithSelectedProject(trustState: .untrusted)

        let blocked = model.blockedCapabilitiesForSkillInstall(
            source: "https://github.com/acme/skills.git",
            scope: .project,
            installer: .git
        )

        XCTAssertEqual(blocked, Set<ExtensibilityCapability>([.network]))
    }

    func testBlockedCapabilitiesForProjectNpxInstallInUntrustedProjectIncludesNetworkAndRuntimeControl() {
        let model = makeModelWithSelectedProject(trustState: .untrusted)

        let blocked = model.blockedCapabilitiesForSkillInstall(
            source: "@acme/skill-pack",
            scope: .project,
            installer: .npx
        )

        XCTAssertEqual(blocked, Set<ExtensibilityCapability>([.network, .runtimeControl]))
    }

    func testBlockedCapabilitiesForProjectGitInstallInUntrustedProjectAllowsLocalPath() {
        let model = makeModelWithSelectedProject(trustState: .untrusted)

        let blocked = model.blockedCapabilitiesForSkillInstall(
            source: "/tmp/local-skill-pack",
            scope: .project,
            installer: .git
        )

        XCTAssertTrue(blocked.isEmpty)
    }

    func testBlockedCapabilitiesForGlobalInstallIgnoresProjectTrustGates() {
        let model = makeModelWithSelectedProject(trustState: .untrusted)

        let blocked = model.blockedCapabilitiesForSkillInstall(
            source: "https://github.com/acme/skills.git",
            scope: .global,
            installer: .git
        )

        XCTAssertTrue(blocked.isEmpty)
    }

    func testInstallSkillSetsBlockedStatusAndSkipsOperationForUntrustedRemoteSource() {
        let model = makeModelWithSelectedProject(trustState: .untrusted)

        model.installSkill(
            source: "https://github.com/acme/skills.git",
            scope: .project,
            installer: .git
        )

        XCTAssertEqual(
            model.skillStatusMessage,
            "Skill install blocked in untrusted project: network."
        )
        XCTAssertFalse(model.isSkillOperationInProgress)
    }

    func testBlockedCapabilitiesForSelectedProjectsIncludesAnyUntrustedTarget() {
        let trustedProjectID = UUID()
        let untrustedProjectID = UUID()
        let model = makeModel(
            projects: [
                ProjectRecord(
                    id: trustedProjectID,
                    name: "Trusted",
                    path: "/tmp/project-\(trustedProjectID.uuidString)",
                    trustState: .trusted
                ),
                ProjectRecord(
                    id: untrustedProjectID,
                    name: "Untrusted",
                    path: "/tmp/project-\(untrustedProjectID.uuidString)",
                    trustState: .untrusted
                ),
            ],
            selectedProjectID: trustedProjectID
        )

        let blocked = model.blockedCapabilitiesForSkillInstall(
            source: "https://github.com/acme/skills.git",
            scope: .project,
            installer: .git,
            projectIDs: [trustedProjectID, untrustedProjectID]
        )

        XCTAssertEqual(blocked, Set([.network]))
    }

    func testInstallSkillToSelectedProjectsBlocksWhenAnyTargetIsUntrusted() {
        let trustedProjectID = UUID()
        let untrustedProjectID = UUID()
        let model = makeModel(
            projects: [
                ProjectRecord(
                    id: trustedProjectID,
                    name: "Trusted",
                    path: "/tmp/project-\(trustedProjectID.uuidString)",
                    trustState: .trusted
                ),
                ProjectRecord(
                    id: untrustedProjectID,
                    name: "Untrusted",
                    path: "/tmp/project-\(untrustedProjectID.uuidString)",
                    trustState: .untrusted
                ),
            ],
            selectedProjectID: trustedProjectID
        )

        model.installSkill(
            source: "https://github.com/acme/skills.git",
            scope: .project,
            installer: .git,
            projectIDs: [trustedProjectID, untrustedProjectID]
        )

        XCTAssertEqual(
            model.skillStatusMessage,
            "Skill install blocked in untrusted project: network."
        )
        XCTAssertFalse(model.isSkillOperationInProgress)
    }

    func testBlockedCapabilitiesForProjectScopedGitUpdateInUntrustedProjectIncludesNetwork() async throws {
        let model = makeModelWithSelectedProject(trustState: .untrusted)
        let item = makeSkillItem(
            scope: .project,
            enabledTargets: [.project],
            updateCapability: .gitUpdate,
            updateSource: "https://github.com/acme/skills.git",
            updateInstaller: .git
        )

        let blocked = try await model.blockedCapabilitiesForSkillMaintenance(item)

        XCTAssertEqual(blocked, Set([.network]))
    }

    func testBlockedCapabilitiesForProjectScopedReinstallInUntrustedProjectIncludesNetworkAndRuntimeControl() async throws {
        let model = makeModelWithSelectedProject(trustState: .untrusted)
        let item = makeSkillItem(
            scope: .project,
            enabledTargets: [.project],
            updateCapability: .reinstall,
            updateSource: "@acme/skill-pack",
            updateInstaller: .npx
        )

        let blocked = try await model.blockedCapabilitiesForSkillMaintenance(item)

        XCTAssertEqual(blocked, Set([.network, .runtimeControl]))
    }

    func testUpdateSkillBlocksGitUpdateForProjectScopedSkillInUntrustedProject() async throws {
        let model = makeModelWithSelectedProject(trustState: .untrusted)
        let item = makeSkillItem(
            scope: .project,
            enabledTargets: [.project],
            updateCapability: .gitUpdate,
            updateSource: "https://github.com/acme/skills.git",
            updateInstaller: .git
        )

        model.updateSkill(item)

        try await waitUntil(timeout: 1.0) {
            model.skillStatusMessage == "Skill update blocked in untrusted project: network."
                && !model.isSkillOperationInProgress
        }
    }

    func testUpdateSkillBlocksReinstallForProjectScopedSkillInUntrustedProject() async throws {
        let model = makeModelWithSelectedProject(trustState: .untrusted)
        let item = makeSkillItem(
            scope: .project,
            enabledTargets: [.project],
            updateCapability: .reinstall,
            updateSource: "@acme/skill-pack",
            updateInstaller: .npx
        )

        model.updateSkill(item)

        try await waitUntil(timeout: 1.0) {
            model.skillStatusMessage == "Skill reinstall blocked in untrusted project: network, runtime-control."
                && !model.isSkillOperationInProgress
        }
    }

    private func makeModelWithSelectedProject(trustState: ProjectTrustState) -> AppModel {
        let projectID = UUID()
        return makeModel(
            projects: [
                ProjectRecord(
                    id: projectID,
                    name: "Project",
                    path: "/tmp/project-\(projectID.uuidString)",
                    trustState: trustState
                ),
            ],
            selectedProjectID: projectID
        )
    }

    private func makeModel(projects: [ProjectRecord], selectedProjectID: UUID) -> AppModel {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        model.projectsState = .loaded(projects)
        model.selectedProjectID = selectedProjectID
        return model
    }

    private func makeSkillItem(
        scope: SkillScope,
        enabledTargets: Set<SkillEnablementTarget>,
        updateCapability: SkillUpdateCapability,
        updateSource: String?,
        updateInstaller: SkillInstallerKind?
    ) -> AppModel.SkillListItem {
        let skillPath = "/tmp/skill-\(UUID().uuidString)"
        let skill = DiscoveredSkill(
            name: "Skill",
            description: "Description",
            scope: scope,
            skillPath: skillPath,
            skillDefinitionPath: "\(skillPath)/SKILL.md",
            hasScripts: false,
            sourceURL: updateSource,
            optionalMetadata: [:],
            installMetadata: updateSource.map {
                SkillInstallMetadata(source: $0, installer: updateInstaller ?? .git)
            },
            isGitRepository: updateCapability == .gitUpdate
        )

        return AppModel.SkillListItem(
            skill: skill,
            enabledTargets: enabledTargets,
            isEnabledForSelectedProject: enabledTargets.contains(.project),
            selectedProjectCount: enabledTargets.contains(.project) ? 1 : nil,
            updateCapability: updateCapability,
            updateSource: updateSource,
            updateInstaller: updateInstaller
        )
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Timed out waiting for condition.")
    }
}
