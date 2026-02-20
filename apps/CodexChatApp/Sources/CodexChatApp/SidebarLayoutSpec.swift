import CoreGraphics

enum SidebarLayoutSpec {
    static let listHorizontalInset: CGFloat = 12
    static let listRowSpacing: CGFloat = 3
    static let rowHorizontalPadding: CGFloat = 8
    static let threadRowHorizontalPadding: CGFloat = 7
    static let rowVerticalPadding: CGFloat = 3
    static let rowMinHeight: CGFloat = 30
    static let searchMinHeight: CGFloat = 38

    static let iconColumnWidth: CGFloat = 20
    static let iconTextGap: CGFloat = 8

    static let controlButtonSize: CGFloat = 24
    static let controlIconFontSize: CGFloat = 13
    static let controlSlotSpacing: CGFloat = 6
    static let threadControlSlotSpacing: CGFloat = 2

    static let threadMetaColumnWidth: CGFloat = (controlButtonSize * 2) + threadControlSlotSpacing
    static let timestampColumnWidth: CGFloat = 44

    static let sectionHeaderTopPadding: CGFloat = 6
    static let sectionHeaderBottomPadding: CGFloat = 1
    static let sectionHeaderLeadingInset: CGFloat = 0
    static let headerActionTrailingPadding: CGFloat = rowHorizontalPadding

    static let selectedRowInset: CGFloat = 0
    static let selectedRowCornerRadius: CGFloat = 10

    static let footerHeight: CGFloat = 58
    static let footerHorizontalInset: CGFloat = listHorizontalInset
    static let footerVerticalInset: CGFloat = 6

    static let projectTrailingWidth: CGFloat = (controlButtonSize * 2) + controlSlotSpacing
    static let threadTrailingWidth: CGFloat = (controlButtonSize * 2) + threadControlSlotSpacing
}
