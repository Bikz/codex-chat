import XCTest
@testable import CodexChatInfra

final class CodexChatInfraTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexChatInfraPackage.version, "0.1.0")
    }
}
