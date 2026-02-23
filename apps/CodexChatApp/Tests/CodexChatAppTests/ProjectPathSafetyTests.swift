@testable import CodexChatShared
import Foundation
import XCTest

final class ProjectPathSafetyTests: XCTestCase {
    func testDestinationURLAllowsNestedProjectPath() {
        let root = "/tmp/codexchat-project"
        let destination = ProjectPathSafety.destinationURL(
            for: "artifacts/notes/summary.md",
            projectPath: root
        )

        XCTAssertEqual(destination?.path, "/tmp/codexchat-project/artifacts/notes/summary.md")
    }

    func testDestinationURLRejectsTraversalOutsideRoot() {
        let root = "/tmp/codexchat-project"
        let destination = ProjectPathSafety.destinationURL(
            for: "../outside.txt",
            projectPath: root
        )

        XCTAssertNil(destination)
    }

    func testDestinationURLRejectsAbsolutePathOutsideRoot() {
        let root = "/tmp/codexchat-project"
        let destination = ProjectPathSafety.destinationURL(
            for: "/tmp/other/place.txt",
            projectPath: root
        )

        XCTAssertNil(destination)
    }

    func testDestinationURLRejectsEmptyPath() {
        let destination = ProjectPathSafety.destinationURL(
            for: "   ",
            projectPath: "/tmp/codexchat-project"
        )

        XCTAssertNil(destination)
    }
}
