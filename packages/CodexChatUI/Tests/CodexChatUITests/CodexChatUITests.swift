import XCTest
@testable import CodexChatUI

final class CodexChatUITests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexChatUIPackage.version, "0.1.0")
    }
}
