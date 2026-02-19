@testable import CodexChatShared
import XCTest

final class SidebarLayoutSpecTests: XCTestCase {
    func testTrailingWidthsMatchControlGeometry() {
        XCTAssertEqual(SidebarLayoutSpec.projectTrailingWidth, 54)
        XCTAssertEqual(SidebarLayoutSpec.threadTrailingWidth, 54)
    }

    func testSectionHeaderLeadingInsetAlignsToIconRailStart() {
        XCTAssertEqual(SidebarLayoutSpec.sectionHeaderLeadingInset, 0)
    }

    func testFooterAndListHorizontalRailsMatch() {
        XCTAssertEqual(SidebarLayoutSpec.listHorizontalInset, 16)
        XCTAssertEqual(SidebarLayoutSpec.footerHorizontalInset, SidebarLayoutSpec.listHorizontalInset)
    }

    func testDenseSidebarSpacingConstants() {
        XCTAssertEqual(SidebarLayoutSpec.selectedRowInset, 1)
        XCTAssertEqual(SidebarLayoutSpec.listRowSpacing, 2)
        XCTAssertEqual(SidebarLayoutSpec.sectionHeaderTopPadding, 12)
        XCTAssertEqual(SidebarLayoutSpec.sectionHeaderBottomPadding, 3)
    }

    func testHeaderActionTrailingPaddingMatchesRowHorizontalPadding() {
        XCTAssertEqual(SidebarLayoutSpec.headerActionTrailingPadding, SidebarLayoutSpec.rowHorizontalPadding)
    }

    func testHitTargetsMeetMinimums() {
        XCTAssertGreaterThanOrEqual(SidebarLayoutSpec.rowMinHeight, 32)
        XCTAssertEqual(SidebarLayoutSpec.controlButtonSize, 24)
    }
}
