import CoreGraphics

enum SidebarLayoutSpec {
    static let listHorizontalInset: CGFloat = 16
    static let rowHorizontalPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 4
    static let rowMinHeight: CGFloat = 32
    static let searchMinHeight: CGFloat = 40

    static let iconColumnWidth: CGFloat = 20
    static let iconTextGap: CGFloat = 8

    static let controlButtonSize: CGFloat = 24
    static let controlIconFontSize: CGFloat = 13
    static let controlSlotSpacing: CGFloat = 6

    static let timestampColumnWidth: CGFloat = 44

    static let sectionHeaderTopPadding: CGFloat = 20
    static let sectionHeaderBottomPadding: CGFloat = 6
    static let sectionHeaderLeadingInset: CGFloat = 0

    static let selectedRowInset: CGFloat = 2
    static let selectedRowCornerRadius: CGFloat = 10

    static let footerHeight: CGFloat = 64
    static let footerHorizontalInset: CGFloat = 16
    static let footerVerticalInset: CGFloat = 8

    static let projectTrailingWidth: CGFloat = (controlButtonSize * 2) + controlSlotSpacing
    static let threadTrailingWidth: CGFloat = (controlButtonSize * 2) + controlSlotSpacing
}
