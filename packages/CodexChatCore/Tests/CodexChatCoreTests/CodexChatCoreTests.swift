@testable import CodexChatCore
import XCTest

final class CodexChatCoreTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(CodexChatCorePackage.version, "0.1.0")
    }
}
