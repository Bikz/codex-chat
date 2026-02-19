@testable import CodexChatShared
import XCTest

final class SidebarLayoutSpecTests: XCTestCase {
    func testTrailingWidthsMatchControlGeometry() {
        XCTAssertEqual(SidebarLayoutSpec.projectTrailingWidth, 54)
        XCTAssertEqual(
            SidebarLayoutSpec.threadTrailingWidth,
            (SidebarLayoutSpec.controlButtonSize * 2) + SidebarLayoutSpec.threadControlSlotSpacing
        )
        XCTAssertGreaterThanOrEqual(
            SidebarLayoutSpec.threadTrailingWidth,
            SidebarLayoutSpec.timestampColumnWidth
        )
    }

    func testSectionHeaderLeadingInsetAlignsToIconRailStart() {
        XCTAssertEqual(SidebarLayoutSpec.sectionHeaderLeadingInset, 0)
    }

    func testFooterAndListHorizontalRailsMatch() {
        XCTAssertEqual(SidebarLayoutSpec.listHorizontalInset, 12)
        XCTAssertEqual(SidebarLayoutSpec.footerHorizontalInset, SidebarLayoutSpec.listHorizontalInset)
    }

    func testDenseSidebarSpacingConstants() {
        XCTAssertEqual(SidebarLayoutSpec.selectedRowInset, 0)
        XCTAssertEqual(SidebarLayoutSpec.listRowSpacing, 4)
        XCTAssertEqual(SidebarLayoutSpec.sectionHeaderTopPadding, 8)
        XCTAssertEqual(SidebarLayoutSpec.sectionHeaderBottomPadding, 2)
    }

    func testHeaderActionTrailingPaddingMatchesRowHorizontalPadding() {
        XCTAssertEqual(SidebarLayoutSpec.headerActionTrailingPadding, SidebarLayoutSpec.rowHorizontalPadding)
    }

    func testHitTargetsMeetMinimums() {
        XCTAssertGreaterThanOrEqual(SidebarLayoutSpec.rowMinHeight, 32)
        XCTAssertEqual(SidebarLayoutSpec.controlButtonSize, 24)
    }
}
