import CodexChatCore
@testable import CodexChatShared
import XCTest

@MainActor
final class ExtensibilityCapabilityPolicyTests: XCTestCase {
    func testBlockedCapabilitiesReturnsOnlyPrivilegedForUntrustedProjects() {
        let required: Set<ExtensibilityCapability> = [
            .projectRead,
            .network,
            .nativeActions,
            .runWhenAppClosed,
        ]

        let blocked = ExtensibilityCapabilityPolicy.blockedCapabilities(
            for: required,
            trustState: .untrusted
        )

        XCTAssertEqual(blocked, Set([.network, .nativeActions, .runWhenAppClosed]))
    }

    func testBlockedCapabilitiesAllowsAllForTrustedProjects() {
        let required: Set<ExtensibilityCapability> = [
            .projectWrite,
            .filesystemWrite,
            .runtimeControl,
        ]

        let blocked = ExtensibilityCapabilityPolicy.blockedCapabilities(
            for: required,
            trustState: .trusted
        )

        XCTAssertTrue(blocked.isEmpty)
    }

    func testPlanRunnerCapabilitiesMapToSharedPolicyVocabulary() {
        let mapped = ExtensibilityCapabilityPolicy.planRunnerCapabilities(
            Set([.nativeActions, .filesystemWrite, .network, .runtimeControl])
        )

        XCTAssertEqual(
            mapped,
            Set([.nativeActions, .filesystemWrite, .network, .runtimeControl])
        )
    }

    func testProjectTrustStateDefaultsToUntrustedForUnknownProjectID() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let selectedProjectID = UUID()
        model.projectsState = .loaded([
            ProjectRecord(
                id: selectedProjectID,
                name: "Trusted Project",
                path: "/tmp/trusted",
                trustState: .trusted
            ),
        ])
        model.selectedProjectID = selectedProjectID

        XCTAssertEqual(model.projectTrustState(for: UUID()), .untrusted)
    }

    func testProjectTrustStateUsesSelectedProjectWhenIDIsNil() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)

        let selectedProjectID = UUID()
        model.projectsState = .loaded([
            ProjectRecord(
                id: selectedProjectID,
                name: "Trusted Project",
                path: "/tmp/trusted",
                trustState: .trusted
            ),
        ])
        model.selectedProjectID = selectedProjectID

        XCTAssertEqual(model.projectTrustState(for: nil), .trusted)
    }
}
