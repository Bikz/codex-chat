import XCTest
@testable import CodexKit

final class CodexKitTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexKitPackage.version, "0.1.0")
    }
}
