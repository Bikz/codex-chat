import CodexChatCore
@testable import CodexChatShared
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

        XCTAssertEqual(blocked, Set([.network]))
    }

    func testBlockedCapabilitiesForProjectNpxInstallInUntrustedProjectIncludesNetworkAndRuntimeControl() {
        let model = makeModelWithSelectedProject(trustState: .untrusted)

        let blocked = model.blockedCapabilitiesForSkillInstall(
            source: "@acme/skill-pack",
            scope: .project,
            installer: .npx
        )

        XCTAssertEqual(blocked, Set([.network, .runtimeControl]))
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
}
