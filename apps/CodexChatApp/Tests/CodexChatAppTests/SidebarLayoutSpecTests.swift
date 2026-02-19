@testable import CodexChatShared
import XCTest

final class SidebarLayoutSpecTests: XCTestCase {
    func testTrailingWidthsMatchControlGeometry() {
        XCTAssertEqual(SidebarLayoutSpec.projectTrailingWidth, 54)
        XCTAssertEqual(SidebarLayoutSpec.threadTrailingWidth, 54)
    }

    func testSectionHeaderLeadingInsetMatchesIconRailMath() {
        XCTAssertEqual(
            SidebarLayoutSpec.sectionHeaderLeadingInset,
            SidebarLayoutSpec.iconColumnWidth + SidebarLayoutSpec.iconTextGap
        )
        XCTAssertEqual(SidebarLayoutSpec.sectionHeaderLeadingInset, 28)
    }

    func testFooterAndListHorizontalRailsMatch() {
        XCTAssertEqual(SidebarLayoutSpec.listHorizontalInset, 16)
        XCTAssertEqual(SidebarLayoutSpec.footerHorizontalInset, SidebarLayoutSpec.listHorizontalInset)
    }

    func testHitTargetsMeetMinimums() {
        XCTAssertGreaterThanOrEqual(SidebarLayoutSpec.rowMinHeight, 32)
        XCTAssertEqual(SidebarLayoutSpec.controlButtonSize, 24)
    }
}
