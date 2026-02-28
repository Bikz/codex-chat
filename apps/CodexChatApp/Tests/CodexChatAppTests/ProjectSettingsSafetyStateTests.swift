import CodexChatCore
@testable import CodexChatShared
import XCTest

@MainActor
final class ProjectSettingsSafetyStateTests: XCTestCase {
    func testClampedNetworkAccessTurnsOffOutsideWorkspaceWrite() {
        XCTAssertTrue(AppModel.clampedNetworkAccess(for: .workspaceWrite, networkAccess: true))
        XCTAssertFalse(AppModel.clampedNetworkAccess(for: .readOnly, networkAccess: true))
        XCTAssertFalse(AppModel.clampedNetworkAccess(for: .dangerFullAccess, networkAccess: true))
    }

    func testProjectSafetySettingsMirrorProjectRecordValues() {
        let project = ProjectRecord(
            name: "Workspace",
            path: "/tmp/workspace",
            trustState: .trusted,
            sandboxMode: .workspaceWrite,
            approvalPolicy: .never,
            networkAccess: true,
            webSearch: .live,
            memoryWriteMode: .summariesAndKeyFacts,
            memoryEmbeddingsEnabled: true
        )

        let settings = ProjectSafetySettings(
            sandboxMode: project.sandboxMode,
            approvalPolicy: project.approvalPolicy,
            networkAccess: project.networkAccess,
            webSearch: project.webSearch
        )

        XCTAssertEqual(settings.sandboxMode, .workspaceWrite)
        XCTAssertEqual(settings.approvalPolicy, .never)
        XCTAssertTrue(settings.networkAccess)
        XCTAssertEqual(settings.webSearch, .live)
    }
}
