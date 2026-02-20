import Foundation

enum SidebarProjectIconResolver {
    static func leadingSymbolName(isExpanded: Bool, isHovered: Bool) -> String {
        guard isHovered else {
            return "folder"
        }
        return isExpanded ? "chevron.down" : "chevron.right"
    }
}
