@testable import CodexChatShared
import XCTest

final class SidebarProjectIconResolverTests: XCTestCase {
    func testLeadingSymbolShowsFolderWhenCollapsedAndNotHovered() {
        XCTAssertEqual(
            SidebarProjectIconResolver.leadingSymbolName(isExpanded: false, isHovered: false),
            "folder"
        )
    }

    func testLeadingSymbolShowsFolderWhenExpandedAndNotHovered() {
        XCTAssertEqual(
            SidebarProjectIconResolver.leadingSymbolName(isExpanded: true, isHovered: false),
            "folder"
        )
    }

    func testLeadingSymbolShowsChevronRightWhenHoveredAndCollapsed() {
        XCTAssertEqual(
            SidebarProjectIconResolver.leadingSymbolName(isExpanded: false, isHovered: true),
            "chevron.right"
        )
    }

    func testLeadingSymbolShowsChevronDownWhenHoveredAndExpanded() {
        XCTAssertEqual(
            SidebarProjectIconResolver.leadingSymbolName(isExpanded: true, isHovered: true),
            "chevron.down"
        )
    }
}
