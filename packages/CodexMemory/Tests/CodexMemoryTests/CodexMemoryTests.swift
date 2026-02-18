import XCTest
@testable import CodexMemory

final class CodexMemoryTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexMemoryPackage.version, "0.1.0")
    }
}
