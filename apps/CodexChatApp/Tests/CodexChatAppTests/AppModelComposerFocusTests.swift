@testable import CodexChatShared
import XCTest

@MainActor
final class AppModelComposerFocusTests: XCTestCase {
    func testBeginDraftChatRequestsComposerFocus() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let projectID = UUID()
        let baseline = model.composerFocusRequestID

        model.beginDraftChat(in: projectID)

        XCTAssertEqual(model.composerFocusRequestID, baseline + 1)
        XCTAssertEqual(model.draftChatProjectID, projectID)
        XCTAssertEqual(model.selectedProjectID, projectID)
    }

    func testStartChatFromEmptyStateFocusesExistingDraft() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let projectID = UUID()
        model.selectedProjectID = projectID
        model.draftChatProjectID = projectID
        let baseline = model.composerFocusRequestID

        model.startChatFromEmptyState()

        XCTAssertEqual(model.composerFocusRequestID, baseline + 1)
        XCTAssertEqual(model.draftChatProjectID, projectID)
    }

    func testStartChatFromEmptyStateCreatesDraftWhenMissing() {
        let model = AppModel(repositories: nil, runtime: nil, bootError: nil)
        let projectID = UUID()
        model.selectedProjectID = projectID
        model.draftChatProjectID = nil
        let baseline = model.composerFocusRequestID

        model.startChatFromEmptyState()

        XCTAssertEqual(model.composerFocusRequestID, baseline + 1)
        XCTAssertEqual(model.selectedProjectID, projectID)
        XCTAssertEqual(model.draftChatProjectID, projectID)
    }
}
