import XCTest
@testable import CodexMods

final class CodexModsTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexModsPackage.version, "0.1.0")
    }
}
