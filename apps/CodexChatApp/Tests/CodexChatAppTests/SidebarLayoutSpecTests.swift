@testable import CodexChatShared
import XCTest

final class SidebarLayoutSpecTests: XCTestCase {
    func testTrailingWidthsMatchControlGeometry() {
        XCTAssertEqual(
            SidebarLayoutSpec.projectTrailingWidth,
            (SidebarLayoutSpec.controlButtonSize * 2) + SidebarLayoutSpec.projectControlSlotSpacing
        )
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
        XCTAssertEqual(SidebarLayoutSpec.listRowSpacing, 2)
        XCTAssertEqual(SidebarLayoutSpec.sectionHeaderTopPadding, 2)
        XCTAssertEqual(SidebarLayoutSpec.sectionHeaderBottomPadding, 0)
    }

    func testHeaderActionTrailingPaddingMatchesRowHorizontalPadding() {
        XCTAssertEqual(SidebarLayoutSpec.headerActionTrailingPadding, SidebarLayoutSpec.rowHorizontalPadding)
        XCTAssertLessThan(SidebarLayoutSpec.threadRowHorizontalPadding, SidebarLayoutSpec.rowHorizontalPadding)
    }

    func testHitTargetsMeetMinimums() {
        XCTAssertGreaterThanOrEqual(SidebarLayoutSpec.rowMinHeight, 29)
        XCTAssertEqual(SidebarLayoutSpec.controlButtonSize, 24)
    }
}
