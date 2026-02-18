import AppKit
import CodexChatCore
import CodexChatUI
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @FocusState private var isSearchFocused: Bool

    @State private var hoveredProjectID: UUID?
    @State private var flashedProjectID: UUID?
    @State private var hoveredThreadID: UUID?
    @State private var isSeeMoreHovered = false

    private let projectsPreviewCount = 3
    private let iconColumnWidth: CGFloat = 18
    private let rowHorizontalPadding: CGFloat = 10
    private let rowVerticalPadding: CGFloat = 8
    private let rowMinimumHeight: CGFloat = 34
    private let controlIconWidth: CGFloat = 18
    private let controlSlotSpacing: CGFloat = 8
    private let projectChevronWidth: CGFloat = 14

    private var projectTrailingWidth: CGFloat {
        projectChevronWidth + (controlIconWidth * 2) + (controlSlotSpacing * 2)
    }

    private var threadTrailingWidth: CGFloat {
        (controlIconWidth * 2) + controlSlotSpacing
    }

    private var sidebarBodyFont: Font {
        .callout
    }

    private var sidebarMetaFont: Font {
        .footnote
    }

    private var sidebarSectionFont: Font {
        .footnote.weight(.semibold)
    }

    private var sidebarBodyIconFont: Font {
        .subheadline
    }

    private var sidebarMetaIconFont: Font {
        .caption
    }

    private var sidebarBackgroundColor: Color {
        Color(hex: tokens.palette.sidebarHex)
    }

    var body: some View {
        List {
            Section {
                searchField

                if isSearchFocused || !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchSurface
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                SidebarActionRow(
                    icon: "square.and.pencil",
                    title: "New chat",
                    iconColumnWidth: iconColumnWidth,
                    horizontalPadding: rowHorizontalPadding,
                    verticalPadding: rowVerticalPadding,
                    minimumHeight: rowMinimumHeight,
                    bodyFont: sidebarBodyFont,
                    iconFont: sidebarBodyIconFont,
                    action: model.createGlobalNewChat
                )

                SidebarActionRow(
                    icon: "wand.and.stars",
                    title: "Skills & Mods",
                    iconColumnWidth: iconColumnWidth,
                    horizontalPadding: rowHorizontalPadding,
                    verticalPadding: rowVerticalPadding,
                    minimumHeight: rowMinimumHeight,
                    bodyFont: sidebarBodyFont,
                    iconFont: sidebarBodyIconFont,
                    isActive: model.detailDestination == .skillsAndMods,
                    iconColor: .secondary,
                    action: model.openSkillsAndMods
                )
            }
            .listRowSeparator(.hidden)

            Section {
                SidebarActionRow(
                    icon: "folder.badge.plus",
                    title: "New Project",
                    iconColumnWidth: iconColumnWidth,
                    horizontalPadding: rowHorizontalPadding,
                    verticalPadding: rowVerticalPadding,
                    minimumHeight: rowMinimumHeight,
                    bodyFont: sidebarBodyFont,
                    iconFont: sidebarBodyIconFont,
                    iconColor: .secondary,
                    action: model.presentNewProjectSheet
                )

                projectRows
            } header: {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: tokens.spacing.small)
                    SidebarSectionHeader(title: "Projects", font: sidebarSectionFont)
                }
            }
            .listRowSeparator(.hidden)

            Section {
                generalThreadRows
            } header: {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: tokens.spacing.small)
                    SidebarSectionHeader(title: "General", font: sidebarSectionFont)
                }
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(sidebarBackgroundColor)
        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
        .safeAreaInset(edge: .bottom) {
            accountRow
        }
        .animation(.easeInOut(duration: 0.2), value: model.expandedProjectIDs)
        .animation(.easeInOut(duration: 0.2), value: model.showAllProjects)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(sidebarBodyIconFont)
                .foregroundStyle(.secondary)
                .frame(width: iconColumnWidth, alignment: .leading)

            TextField(
                "Search",
                text: Binding(
                    get: { model.searchQuery },
                    set: { model.updateSearchQuery($0) }
                )
            )
            .textFieldStyle(.plain)
            .font(sidebarBodyFont)
            .focused($isSearchFocused)
            .accessibilityLabel("Search")
            .accessibilityHint("Searches thread titles and message history")

            if !model.searchQuery.isEmpty {
                Button {
                    model.updateSearchQuery("")
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(sidebarMetaIconFont)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, rowHorizontalPadding)
        .padding(.vertical, rowVerticalPadding - 1)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isSearchFocused ? 0.85 : 0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSearchFocused ? Color.primary.opacity(0.18) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }

    @ViewBuilder
    private var projectRows: some View {
        let visibleProjects = model.showAllProjects
            ? model.namedProjects
            : Array(model.namedProjects.prefix(projectsPreviewCount))

        ForEach(visibleProjects) { project in
            projectRow(project)

            if model.expandedProjectIDs.contains(project.id), model.selectedProjectID == project.id {
                ForEach(model.threads) { thread in
                    threadRow(thread, leadingInset: iconColumnWidth + 8)
                }
            }
        }

        if model.namedProjects.count > projectsPreviewCount {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    model.showAllProjects.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.showAllProjects ? "chevron.up" : "ellipsis")
                        .font(sidebarMetaIconFont)
                        .foregroundStyle(.secondary)
                        .frame(width: iconColumnWidth, alignment: .leading)
                    Text(model.showAllProjects ? "Show less" : "See more")
                        .font(sidebarMetaFont)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, rowHorizontalPadding)
                .padding(.vertical, 6)
                .frame(minHeight: rowMinimumHeight)
            }
            .buttonStyle(SidebarRowButtonStyle(
                isHovered: isSeeMoreHovered
            ))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSeeMoreHovered = hovering
                }
            }
        }
    }

    private func projectRow(_ project: ProjectRecord) -> some View {
        let isExpanded = model.expandedProjectIDs.contains(project.id)
        let isSelected = model.selectedProjectID == project.id
        let isHovered = hoveredProjectID == project.id
        let isFlashed = flashedProjectID == project.id

        return HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(sidebarBodyIconFont)
                .foregroundStyle(.secondary)
                .frame(width: iconColumnWidth, alignment: .leading)

            Text(project.name)
                .font(sidebarBodyFont)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 6)

            HStack(spacing: controlSlotSpacing) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(sidebarMetaIconFont)
                    .foregroundStyle(.secondary)
                    .frame(width: projectChevronWidth, height: controlIconWidth, alignment: .center)
                    .opacity(isHovered ? 1 : 0)

                Button {
                    if model.selectedProjectID != project.id {
                        model.selectProject(project.id)
                    }
                    model.createThread(in: project.id)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(sidebarMetaIconFont)
                        .foregroundStyle(.secondary)
                        .frame(width: controlIconWidth, height: controlIconWidth)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New thread")
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)

                Button {
                    if model.selectedProjectID != project.id {
                        model.selectProject(project.id)
                    }
                    model.showProjectSettings()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(sidebarMetaIconFont)
                        .foregroundStyle(.secondary)
                        .frame(width: controlIconWidth, height: controlIconWidth)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Project settings")
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
            .frame(width: projectTrailingWidth, alignment: .trailing)
        }
        .padding(.horizontal, rowHorizontalPadding)
        .padding(.vertical, rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: rowMinimumHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowFillColor(isActive: isSelected, isHovered: isHovered || isFlashed))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredProjectID = hovering ? project.id : (hoveredProjectID == project.id ? nil : hoveredProjectID)
            }
        }
        .onTapGesture {
            flashedProjectID = project.id
            withAnimation(.easeInOut(duration: 0.18)) {
                model.toggleProjectExpanded(project.id)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                if flashedProjectID == project.id {
                    flashedProjectID = nil
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(project.name)
    }

    @ViewBuilder
    private var generalThreadRows: some View {
        switch model.generalThreadsState {
        case .idle, .loading, .failed:
            EmptyView()
        case let .loaded(threads):
            ForEach(threads) { thread in
                threadRow(thread, leadingInset: iconColumnWidth + 8)
            }
        }
    }

    private func threadRow(_ thread: ThreadRecord, leadingInset: CGFloat) -> some View {
        let isSelected = model.selectedThreadID == thread.id
        let isHovered = hoveredThreadID == thread.id

        return HStack(spacing: 8) {
            Spacer().frame(width: leadingInset)

            Text(thread.title)
                .font(sidebarBodyFont)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 6)

            ZStack(alignment: .trailing) {
                Text(compactRelativeAge(from: thread.updatedAt))
                    .font(sidebarMetaFont)
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 0 : 1)
                    .allowsHitTesting(false)

                HStack(spacing: controlSlotSpacing) {
                    Button {
                        model.togglePin(threadID: thread.id)
                    } label: {
                        Image(systemName: thread.isPinned ? "pin.fill" : "pin")
                            .font(sidebarMetaIconFont)
                            .foregroundStyle(.secondary)
                            .frame(width: controlIconWidth, height: controlIconWidth)
                    }
                    .buttonStyle(.plain)
                    .help(thread.isPinned ? "Unpin chat" : "Pin chat")

                    Button {
                        model.archiveThread(threadID: thread.id)
                    } label: {
                        Image(systemName: "archivebox")
                            .font(sidebarMetaIconFont)
                            .foregroundStyle(.secondary)
                            .frame(width: controlIconWidth, height: controlIconWidth)
                    }
                    .buttonStyle(.plain)
                    .help("Archive chat")
                }
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
            .frame(width: threadTrailingWidth, alignment: .trailing)
        }
        .padding(.horizontal, rowHorizontalPadding)
        .padding(.vertical, rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: rowMinimumHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowFillColor(isActive: isSelected, isHovered: isHovered))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture {
            model.selectThread(thread.id)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredThreadID = hovering ? thread.id : (hoveredThreadID == thread.id ? nil : hoveredThreadID)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(thread.title)
    }

    private func rowFillColor(isActive: Bool, isHovered: Bool) -> Color {
        if isActive {
            return Color.primary.opacity(0.10)
        }
        if isHovered {
            return Color.primary.opacity(0.08)
        }
        return .clear
    }

    private func compactRelativeAge(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        let minute = 60
        let hour = 3600
        let day = 86400
        let week = 604_800

        if seconds < minute {
            return "now"
        }
        if seconds < hour {
            return "\(seconds / minute)m"
        }
        if seconds < day {
            return "\(seconds / hour)h"
        }
        if seconds < week {
            return "\(seconds / day)d"
        }
        return "\(seconds / week)w"
    }

    @ViewBuilder
    private var searchSurface: some View {
        switch model.searchState {
        case .idle:
            EmptyStateView(
                title: "Search ready",
                message: "Results appear as you type.",
                systemImage: "magnifyingglass"
            )
        case .loading:
            LoadingStateView(title: "Searching…")
        case let .failed(message):
            ErrorStateView(title: "Search unavailable", message: message, actionLabel: "Retry") {
                model.updateSearchQuery(model.searchQuery)
            }
        case let .loaded(results) where results.isEmpty:
            EmptyStateView(
                title: "No results",
                message: "Try a different keyword.",
                systemImage: "magnifyingglass"
            )
        case let .loaded(results):
            ForEach(results) { result in
                Button {
                    model.selectSearchResult(result)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.source.capitalized)
                            .font(sidebarMetaFont.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(result.excerpt)
                            .font(sidebarMetaFont)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(SidebarRowButtonStyle())
            }
        }
    }

    private var accountRow: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.4)

            Button {
                openSettingsWindow()
            } label: {
                HStack(spacing: 10) {
                    UserInitialCircle(model.accountDisplayName, size: 28)

                    Text(model.accountDisplayName)
                        .font(sidebarBodyFont.weight(.medium))
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                        .font(sidebarBodyFont)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account and settings")
            .accessibilityHint("Opens global CodexChat settings and General project controls")
        }
        .background(sidebarBackgroundColor)
    }

    private func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SidebarActionRow: View {
    let icon: String
    let title: String
    let iconColumnWidth: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minimumHeight: CGFloat
    let bodyFont: Font
    let iconFont: Font
    let isActive: Bool
    let iconColor: Color
    let action: () -> Void

    @State private var isHovered = false

    init(
        icon: String,
        title: String,
        iconColumnWidth: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        minimumHeight: CGFloat,
        bodyFont: Font,
        iconFont: Font,
        isActive: Bool = false,
        iconColor: Color = .secondary,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.iconColumnWidth = iconColumnWidth
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.minimumHeight = minimumHeight
        self.bodyFont = bodyFont
        self.iconFont = iconFont
        self.isActive = isActive
        self.iconColor = iconColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(iconFont)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
                    .frame(width: iconColumnWidth, alignment: .leading)

                Text(title)
                    .font(bodyFont)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: minimumHeight)
        }
        .buttonStyle(SidebarRowButtonStyle(
            isActive: isActive,
            isHovered: isHovered
        ))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
