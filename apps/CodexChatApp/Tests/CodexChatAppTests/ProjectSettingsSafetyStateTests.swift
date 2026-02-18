import CodexChatCore
@testable import CodexChatShared
import XCTest

@MainActor
final class ProjectSettingsSafetyStateTests: XCTestCase {
    func testClampedNetworkAccessTurnsOffOutsideWorkspaceWrite() {
        XCTAssertTrue(ProjectSettingsSheet.clampedNetworkAccess(for: .workspaceWrite, networkAccess: true))
        XCTAssertFalse(ProjectSettingsSheet.clampedNetworkAccess(for: .readOnly, networkAccess: true))
        XCTAssertFalse(ProjectSettingsSheet.clampedNetworkAccess(for: .dangerFullAccess, networkAccess: true))
    }

    func testSafetyDraftMirrorsSelectedProjectValues() {
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

        let draft = ProjectSettingsSheet.safetyDraft(from: project)

        XCTAssertEqual(draft.sandboxMode, .workspaceWrite)
        XCTAssertEqual(draft.approvalPolicy, .never)
        XCTAssertTrue(draft.networkAccess)
        XCTAssertEqual(draft.webSearchMode, .live)
    }
}
