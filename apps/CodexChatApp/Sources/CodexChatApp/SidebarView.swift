import AppKit
import CodexChatCore
import CodexChatUI
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings
    @FocusState private var isSearchFocused: Bool

    @State private var hoveredProjectID: UUID?
    @State private var flashedProjectID: UUID?
    @State private var hoveredThreadID: UUID?
    @State private var isSeeMoreHovered = false

    private let projectsPreviewCount = 3
    private let iconColumnWidth: CGFloat = 18
    private let rowHorizontalPadding: CGFloat = 8
    private let rowVerticalPadding: CGFloat = 3
    private let rowMinimumHeight: CGFloat = 28
    private let controlIconWidth: CGFloat = 18
    private let controlSlotSpacing: CGFloat = 6

    private var projectTrailingWidth: CGFloat {
        (controlIconWidth * 2) + controlSlotSpacing
    }

    private var threadTrailingWidth: CGFloat {
        (controlIconWidth * 2) + controlSlotSpacing
    }

    private var sidebarBodyFont: Font {
        .system(size: 14, weight: .regular)
    }

    private var sidebarMetaFont: Font {
        .system(size: 12, weight: .regular)
    }

    private var sidebarSectionFont: Font {
        .system(size: 11.5, weight: .semibold)
    }

    private var sidebarBodyIconFont: Font {
        .system(size: 13, weight: .regular)
    }

    private var sidebarMetaIconFont: Font {
        .system(size: 11, weight: .semibold)
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
                    action: model.openSkillsAndMods
                )
            }
            .listRowSeparator(.hidden)

            Section {
                projectRows
            } header: {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: tokens.spacing.xSmall)
                    SidebarSectionHeader(
                        title: "Projects",
                        font: sidebarSectionFont,
                        actionSystemImage: "plus",
                        actionAccessibilityLabel: "New project",
                        trailingAlignmentWidth: threadTrailingWidth,
                        trailingPadding: rowHorizontalPadding,
                        action: model.presentNewProjectSheet
                    )
                }
            }
            .listRowSeparator(.hidden)

            Section {
                generalThreadRows
            } header: {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: tokens.spacing.xSmall)
                    SidebarSectionHeader(
                        title: "General",
                        font: sidebarSectionFont,
                        actionSystemImage: "square.and.pencil",
                        actionAccessibilityLabel: "New chat",
                        trailingAlignmentWidth: threadTrailingWidth,
                        trailingPadding: rowHorizontalPadding,
                        action: model.createGlobalNewChat
                    )
                }
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(sidebarBackgroundColor)
        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
        .safeAreaInset(edge: .bottom) {
            accountRow
        }
        .animation(.easeInOut(duration: tokens.motion.transitionDuration), value: model.expandedProjectIDs)
        .animation(.easeInOut(duration: tokens.motion.transitionDuration), value: model.showAllProjects)
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
            .onChange(of: isSearchFocused) { _, focused in
                #if DEBUG
                    if focused {
                        NSLog("Sidebar search focused")
                    }
                #endif
            }

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
        .padding(.vertical, rowVerticalPadding + 1)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(searchFieldFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    searchFieldBorderColor,
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: tokens.motion.transitionDuration), value: isSearchFocused)
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
                    threadRow(thread, isGeneralThread: false)
                }
            }
        }

        if model.namedProjects.count > projectsPreviewCount {
            Button {
                withAnimation(.easeInOut(duration: tokens.motion.transitionDuration)) {
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
                withAnimation(.easeInOut(duration: tokens.motion.hoverDuration)) {
                    isSeeMoreHovered = hovering
                }
            }
        }
    }

    private func projectRow(_ project: ProjectRecord) -> some View {
        let isExpanded = model.expandedProjectIDs.contains(project.id)
        let isSelected = model.isProjectSidebarVisuallySelected(project.id)
        let isHovered = hoveredProjectID == project.id
        let isFlashed = flashedProjectID == project.id

        return ZStack(alignment: .trailing) {
            Button {
                flashedProjectID = project.id
                withAnimation(.easeInOut(duration: tokens.motion.transitionDuration)) {
                    model.toggleProjectExpanded(project.id)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    if flashedProjectID == project.id {
                        flashedProjectID = nil
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: projectLeadingIconName(isExpanded: isExpanded, isHovered: isHovered))
                        .font(sidebarBodyIconFont)
                        .foregroundStyle(.secondary)
                        .frame(width: iconColumnWidth, alignment: .leading)

                    Text(project.name)
                        .font(sidebarBodyFont)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 6)

                    Color.clear
                        .frame(width: projectTrailingWidth)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, rowHorizontalPadding)
                .padding(.vertical, rowVerticalPadding)
                .frame(maxWidth: .infinity, minHeight: rowMinimumHeight, alignment: .leading)
            }
            .buttonStyle(SidebarRowButtonStyle(
                isActive: isSelected,
                cornerRadius: 5,
                isHovered: isHovered || isFlashed
            ))
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel(project.name)
            .accessibilityHint("Selects this project and toggles its thread list.")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            HStack(spacing: controlSlotSpacing) {
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
                .accessibilityLabel("New thread in \(project.name)")
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
                .accessibilityLabel("Open settings for \(project.name)")
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
            .frame(width: projectTrailingWidth, alignment: .trailing)
            .padding(.trailing, rowHorizontalPadding)
        }
        .frame(maxWidth: .infinity, minHeight: rowMinimumHeight, alignment: .leading)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: tokens.motion.hoverDuration)) {
                hoveredProjectID = hovering ? project.id : (hoveredProjectID == project.id ? nil : hoveredProjectID)
            }
        }
    }

    @ViewBuilder
    private var generalThreadRows: some View {
        switch model.generalThreadsState {
        case .idle, .loading, .failed:
            EmptyView()
        case let .loaded(threads):
            ForEach(threads) { thread in
                threadRow(thread, isGeneralThread: true)
            }
        }
    }

    private func threadRow(_ thread: ThreadRecord, isGeneralThread: Bool) -> some View {
        let isSelected = model.selectedThreadID == thread.id
        let isHovered = hoveredThreadID == thread.id

        return ZStack(alignment: .trailing) {
            Button {
                model.selectThread(thread.id)
            } label: {
                HStack(spacing: 8) {
                    if !isGeneralThread {
                        threadStatusMarker(for: thread.id)
                    }

                    Text(thread.title)
                        .font(sidebarBodyFont)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 6)

                    Color.clear
                        .frame(width: threadTrailingWidth)
                        .accessibilityHidden(true)
                }
                .padding(.leading, isGeneralThread ? 0 : rowHorizontalPadding)
                .padding(.trailing, rowHorizontalPadding)
                .padding(.vertical, rowVerticalPadding)
                .frame(maxWidth: .infinity, minHeight: rowMinimumHeight, alignment: .leading)
            }
            .buttonStyle(SidebarRowButtonStyle(
                isActive: isSelected,
                cornerRadius: 5,
                isHovered: isHovered
            ))
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel(thread.title)
            .accessibilityHint(threadStatusHint(threadID: thread.id))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

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
                    .accessibilityLabel(thread.isPinned ? "Unpin \(thread.title)" : "Pin \(thread.title)")

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
                    .accessibilityLabel("Archive \(thread.title)")
                }
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
            .frame(width: threadTrailingWidth, alignment: .trailing)
            .padding(.trailing, rowHorizontalPadding)
        }
        .frame(maxWidth: .infinity, minHeight: rowMinimumHeight, alignment: .leading)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: tokens.motion.hoverDuration)) {
                hoveredThreadID = hovering ? thread.id : (hoveredThreadID == thread.id ? nil : hoveredThreadID)
            }
        }
    }

    @ViewBuilder
    private func threadStatusMarker(for threadID: UUID) -> some View {
        if model.isThreadWorking(threadID) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.72)
                .frame(width: iconColumnWidth, alignment: .leading)
                .accessibilityLabel("Working")
        } else if model.isThreadUnread(threadID) {
            Circle()
                .fill(Color(hex: tokens.palette.accentHex).opacity(0.9))
                .frame(width: 8, height: 8)
                .frame(width: iconColumnWidth, alignment: .leading)
                .accessibilityLabel("Unread updates")
        } else {
            Color.clear
                .frame(width: iconColumnWidth, height: 8, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    private func threadStatusHint(threadID: UUID) -> String {
        if model.isThreadWorking(threadID) {
            return "Codex is currently working in this chat."
        }
        if model.isThreadUnread(threadID) {
            return "This chat has unread updates."
        }
        return "Open chat."
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
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account and settings")
            .accessibilityHint("Opens global CodexChat settings and General project controls")
        }
        .background(sidebarBackgroundColor)
    }

    private func openSettingsWindow() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private var searchFieldFillColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(isSearchFocused ? 0.14 : 0.10)
        }
        return Color.black.opacity(isSearchFocused ? 0.055 : 0.04)
    }

    private var searchFieldBorderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(isSearchFocused ? 0.18 : 0.12)
        }
        return Color.black.opacity(isSearchFocused ? 0.12 : 0.07)
    }

    private func projectLeadingIconName(isExpanded: Bool, isHovered: Bool) -> String {
        if isExpanded || isHovered {
            return isExpanded ? "chevron.down" : "chevron.right"
        }
        return "folder"
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
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.designTokens) private var tokens
    @Environment(\.colorScheme) private var colorScheme

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
        self.action = action
    }

    private var actionIconColor: Color {
        if colorScheme == .dark {
            return Color.primary.opacity(0.85)
        }
        return Color.primary.opacity(0.68)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(iconFont)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(actionIconColor)
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
            withAnimation(.easeInOut(duration: tokens.motion.hoverDuration)) {
                isHovered = hovering
            }
        }
    }
}
