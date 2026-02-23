@testable import CodexChatShared
import CodexKit
import XCTest

final class ModChangesReviewSheetTests: XCTestCase {
    func testIndexedChangesAssignUniqueIDsForDuplicateEntries() {
        let duplicate = RuntimeFileChange(path: "README.md", kind: "modified", diff: "@@ -1 +1 @@")
        let changes = [duplicate, duplicate]

        let indexed = ModChangesReviewSheet.indexedChanges(changes)

        XCTAssertEqual(indexed.count, 2)
        XCTAssertEqual(indexed.map(\.id), [0, 1])
        XCTAssertEqual(indexed.map(\.change), changes)
    }

    func testIndexedChangesReturnsEmptyForEmptyInput() {
        XCTAssertTrue(ModChangesReviewSheet.indexedChanges([]).isEmpty)
    }
}
