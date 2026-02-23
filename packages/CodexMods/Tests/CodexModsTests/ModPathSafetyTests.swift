@testable import CodexMods
import XCTest

final class ModPathSafetyTests: XCTestCase {
    func testNormalizedSafeRelativePathRejectsUnsafeValues() {
        XCTAssertEqual(ModPathSafety.normalizedSafeRelativePath("mods/personal-notes"), "mods/personal-notes")
        XCTAssertEqual(ModPathSafety.normalizedSafeRelativePath("  scripts/run.sh  "), "scripts/run.sh")
        XCTAssertNil(ModPathSafety.normalizedSafeRelativePath(nil))
        XCTAssertNil(ModPathSafety.normalizedSafeRelativePath(""))
        XCTAssertNil(ModPathSafety.normalizedSafeRelativePath("/absolute/path"))
        XCTAssertNil(ModPathSafety.normalizedSafeRelativePath("../escape"))
        XCTAssertNil(ModPathSafety.normalizedSafeRelativePath("mods/../escape"))
    }

    func testIsWithinRootRequiresDescendantPath() {
        let root = URL(fileURLWithPath: "/tmp/codexmods-root", isDirectory: true)
        let child = URL(fileURLWithPath: "/tmp/codexmods-root/subdir/ui.mod.json", isDirectory: false)
        let sibling = URL(fileURLWithPath: "/tmp/codexmods-other/ui.mod.json", isDirectory: false)

        XCTAssertTrue(ModPathSafety.isWithinRoot(candidateURL: root, rootURL: root))
        XCTAssertTrue(ModPathSafety.isWithinRoot(candidateURL: child, rootURL: root))
        XCTAssertFalse(ModPathSafety.isWithinRoot(candidateURL: sibling, rootURL: root))
    }
}
