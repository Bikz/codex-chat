import XCTest
@testable import CodexSkills

final class CodexSkillsTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexSkillsPackage.version, "0.1.0")
    }
}
