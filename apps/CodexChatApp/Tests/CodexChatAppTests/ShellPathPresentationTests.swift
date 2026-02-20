@testable import CodexChatShared
import XCTest

final class ShellPathPresentationTests: XCTestCase {
    func testCompactPathCollapsesHomeDirectory() {
        let path = "/Users/bikram/Developer/CodexChat"
        let compact = ShellPathPresentation.compactPath(path, homeDirectory: "/Users/bikram")
        XCTAssertEqual(compact, "~/Developer/CodexChat")
    }

    func testCompactPathReturnsTildeForHomeRoot() {
        let compact = ShellPathPresentation.compactPath("/Users/bikram", homeDirectory: "/Users/bikram")
        XCTAssertEqual(compact, "~")
    }

    func testCompactPathKeepsNonHomePaths() {
        let compact = ShellPathPresentation.compactPath("/tmp/project", homeDirectory: "/Users/bikram")
        XCTAssertEqual(compact, "/tmp/project")
    }

    func testLeafNameUsesLastDirectory() {
        let leaf = ShellPathPresentation.leafName(for: "/Users/bikram/Developer/CodexChat")
        XCTAssertEqual(leaf, "CodexChat")
    }

    func testLeafNameHandlesRootAndEmptyPaths() {
        XCTAssertEqual(ShellPathPresentation.leafName(for: "/"), "/")
        XCTAssertEqual(ShellPathPresentation.leafName(for: ""), "Shell")
    }
}
