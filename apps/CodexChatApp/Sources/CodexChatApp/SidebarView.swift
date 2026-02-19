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
    @State private var isThreadSelectionSuppressed = false
    @State private var threadSelectionSuppressionGeneration = 0

    private let projectsPreviewCount = 3

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
        .system(size: 14, weight: .regular)
    }

    private var sidebarMetaIconFont: Font {
        .system(size: SidebarLayoutSpec.controlIconFontSize, weight: .semibold)
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
                    iconColumnWidth: SidebarLayoutSpec.iconColumnWidth,
                    iconTextGap: SidebarLayoutSpec.iconTextGap,
                    horizontalPadding: SidebarLayoutSpec.rowHorizontalPadding,
                    verticalPadding: SidebarLayoutSpec.rowVerticalPadding,
                    minimumHeight: SidebarLayoutSpec.rowMinHeight,
                    bodyFont: sidebarBodyFont,
                    iconFont: sidebarBodyIconFont,
                    cornerRadius: SidebarLayoutSpec.selectedRowCornerRadius,
                    horizontalInset: SidebarLayoutSpec.selectedRowInset,
                    action: model.createGlobalNewChat
                )

                SidebarActionRow(
                    icon: "wand.and.stars",
                    title: "Skills & Mods",
                    iconColumnWidth: SidebarLayoutSpec.iconColumnWidth,
                    iconTextGap: SidebarLayoutSpec.iconTextGap,
                    horizontalPadding: SidebarLayoutSpec.rowHorizontalPadding,
                    verticalPadding: SidebarLayoutSpec.rowVerticalPadding,
                    minimumHeight: SidebarLayoutSpec.rowMinHeight,
                    bodyFont: sidebarBodyFont,
                    iconFont: sidebarBodyIconFont,
                    cornerRadius: SidebarLayoutSpec.selectedRowCornerRadius,
                    horizontalInset: SidebarLayoutSpec.selectedRowInset,
                    isActive: model.detailDestination == .skillsAndMods,
                    action: model.openSkillsAndMods
                )
            }
            .listRowSeparator(.hidden)

            Section {
                projectRows
            } header: {
                SidebarSectionHeader(
                    title: "Projects",
                    font: sidebarSectionFont,
                    actionSystemImage: "plus",
                    actionAccessibilityLabel: "New project",
                    trailingAlignmentWidth: SidebarLayoutSpec.projectTrailingWidth,
                    horizontalPadding: SidebarLayoutSpec.selectedRowInset + SidebarLayoutSpec.rowHorizontalPadding,
                    trailingPadding: SidebarLayoutSpec.headerActionTrailingPadding,
                    leadingInset: SidebarLayoutSpec.sectionHeaderLeadingInset,
                    topPadding: SidebarLayoutSpec.sectionHeaderTopPadding,
                    bottomPadding: SidebarLayoutSpec.sectionHeaderBottomPadding,
                    actionSlotSize: SidebarLayoutSpec.controlButtonSize,
                    actionSymbolSize: SidebarLayoutSpec.controlIconFontSize,
                    titleTracking: 0.3,
                    action: model.presentNewProjectSheet
                )
            }
            .listRowSeparator(.hidden)

            Section {
                generalThreadRows
            } header: {
                SidebarSectionHeader(
                    title: "General",
                    font: sidebarSectionFont,
                    actionSystemImage: "square.and.pencil",
                    actionAccessibilityLabel: "New chat",
                    trailingAlignmentWidth: SidebarLayoutSpec.threadTrailingWidth,
                    horizontalPadding: SidebarLayoutSpec.selectedRowInset + SidebarLayoutSpec.rowHorizontalPadding,
                    trailingPadding: SidebarLayoutSpec.headerActionTrailingPadding,
                    leadingInset: SidebarLayoutSpec.sectionHeaderLeadingInset,
                    topPadding: SidebarLayoutSpec.sectionHeaderTopPadding,
                    bottomPadding: SidebarLayoutSpec.sectionHeaderBottomPadding,
                    actionSlotSize: SidebarLayoutSpec.controlButtonSize,
                    actionSymbolSize: SidebarLayoutSpec.controlIconFontSize,
                    titleTracking: 0.3,
                    action: model.createGlobalNewChat
                )
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(sidebarBackgroundColor)
        .listRowInsets(EdgeInsets(
            top: 0,
            leading: SidebarLayoutSpec.listHorizontalInset,
            bottom: 0,
            trailing: SidebarLayoutSpec.listHorizontalInset
        ))
        .safeAreaInset(edge: .bottom) {
            accountRow
        }
        .animation(.easeInOut(duration: tokens.motion.transitionDuration), value: model.expandedProjectIDs)
        .animation(.easeInOut(duration: tokens.motion.transitionDuration), value: model.showAllProjects)
    }

    private var searchField: some View {
        HStack(spacing: SidebarLayoutSpec.iconTextGap) {
            Image(systemName: "magnifyingglass")
                .font(sidebarBodyIconFont)
                .foregroundStyle(.secondary)
                .frame(width: SidebarLayoutSpec.iconColumnWidth, alignment: .leading)

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
        .padding(.horizontal, SidebarLayoutSpec.rowHorizontalPadding)
        .padding(.vertical, SidebarLayoutSpec.rowVerticalPadding)
        .frame(minHeight: SidebarLayoutSpec.searchMinHeight)
        .background(
            RoundedRectangle(cornerRadius: SidebarLayoutSpec.selectedRowCornerRadius, style: .continuous)
                .fill(searchFieldFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SidebarLayoutSpec.selectedRowCornerRadius, style: .continuous)
                .strokeBorder(
                    searchFieldBorderColor,
                    lineWidth: 1
                )
        )
        .padding(.horizontal, SidebarLayoutSpec.selectedRowInset)
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
                let projectThreads = model.threads.filter { $0.projectId == project.id }
                ForEach(projectThreads) { thread in
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
                HStack(spacing: SidebarLayoutSpec.iconTextGap) {
                    Image(systemName: model.showAllProjects ? "chevron.up" : "ellipsis")
                        .font(sidebarMetaIconFont)
                        .foregroundStyle(.secondary)
                        .frame(width: SidebarLayoutSpec.iconColumnWidth, alignment: .leading)
                    Text(model.showAllProjects ? "Show less" : "See more")
                        .font(sidebarMetaFont)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, SidebarLayoutSpec.rowHorizontalPadding)
                .padding(.vertical, 6)
                .frame(minHeight: SidebarLayoutSpec.rowMinHeight)
            }
            .buttonStyle(SidebarRowButtonStyle(
                cornerRadius: SidebarLayoutSpec.selectedRowCornerRadius,
                isHovered: isSeeMoreHovered
            ))
            .padding(.horizontal, SidebarLayoutSpec.selectedRowInset)
            .onHover { hovering in
                guard isSeeMoreHovered != hovering else {
                    return
                }
                isSeeMoreHovered = hovering
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
                HStack(spacing: SidebarLayoutSpec.iconTextGap) {
                    Image(systemName: projectLeadingIconName(isExpanded: isExpanded, isHovered: isHovered))
                        .font(sidebarBodyIconFont)
                        .foregroundStyle(.secondary)
                        .frame(width: SidebarLayoutSpec.iconColumnWidth, alignment: .leading)

                    Text(project.name)
                        .font(sidebarBodyFont)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer(minLength: SidebarLayoutSpec.controlSlotSpacing)

                    Color.clear
                        .frame(width: SidebarLayoutSpec.projectTrailingWidth)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, SidebarLayoutSpec.rowHorizontalPadding)
                .padding(.vertical, SidebarLayoutSpec.rowVerticalPadding)
                .frame(maxWidth: .infinity, minHeight: SidebarLayoutSpec.rowMinHeight, alignment: .leading)
            }
            .buttonStyle(SidebarRowButtonStyle(
                isActive: isSelected,
                cornerRadius: SidebarLayoutSpec.selectedRowCornerRadius,
                isHovered: isHovered || isFlashed
            ))
            .contentShape(RoundedRectangle(cornerRadius: SidebarLayoutSpec.selectedRowCornerRadius, style: .continuous))
            .accessibilityLabel(project.name)
            .accessibilityHint("Selects this project and toggles its thread list.")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            HStack(spacing: SidebarLayoutSpec.controlSlotSpacing) {
                Button {
                    if model.selectedProjectID != project.id {
                        model.selectProject(project.id)
                    }
                    model.createThread(in: project.id)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(sidebarMetaIconFont)
                        .foregroundStyle(.secondary)
                        .frame(width: SidebarLayoutSpec.controlButtonSize, height: SidebarLayoutSpec.controlButtonSize)
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
                        .frame(width: SidebarLayoutSpec.controlButtonSize, height: SidebarLayoutSpec.controlButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Project settings")
                .accessibilityLabel("Open settings for \(project.name)")
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
            .frame(width: SidebarLayoutSpec.projectTrailingWidth, alignment: .trailing)
            .padding(.trailing, SidebarLayoutSpec.rowHorizontalPadding)
        }
        .padding(.horizontal, SidebarLayoutSpec.selectedRowInset)
        .frame(maxWidth: .infinity, minHeight: SidebarLayoutSpec.rowMinHeight, alignment: .leading)
        .onHover { hovering in
            let nextHoveredID = hovering ? project.id : nil
            guard hoveredProjectID != nextHoveredID else {
                return
            }
            hoveredProjectID = nextHoveredID
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
        let rowSpacing = isGeneralThread ? 0 : SidebarLayoutSpec.iconTextGap
        let isAwaitingInput = model.hasPendingApproval(for: thread.id)

        return ZStack(alignment: .trailing) {
            Button {
                guard !isThreadSelectionSuppressed else {
                    return
                }
                model.selectThread(thread.id)
            } label: {
                HStack(spacing: rowSpacing) {
                    if !isGeneralThread {
                        threadStatusMarker(for: thread.id)
                    }

                    if !isGeneralThread, thread.isPinned {
                        Image(systemName: "star.fill")
                            .font(sidebarMetaIconFont)
                            .foregroundStyle(Color(hex: tokens.palette.accentHex).opacity(0.9))
                    }

                    Text(thread.title)
                        .font(sidebarBodyFont)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer(minLength: SidebarLayoutSpec.threadControlSlotSpacing)

                    Color.clear
                        .frame(width: SidebarLayoutSpec.threadTrailingWidth)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, SidebarLayoutSpec.rowHorizontalPadding)
                .padding(.vertical, SidebarLayoutSpec.rowVerticalPadding)
                .frame(maxWidth: .infinity, minHeight: SidebarLayoutSpec.rowMinHeight, alignment: .leading)
            }
            .buttonStyle(SidebarRowButtonStyle(
                isActive: isSelected,
                cornerRadius: SidebarLayoutSpec.selectedRowCornerRadius,
                isHovered: isHovered
            ))
            .contentShape(RoundedRectangle(cornerRadius: SidebarLayoutSpec.selectedRowCornerRadius, style: .continuous))
            .accessibilityLabel(thread.title)
            .accessibilityHint(threadStatusHint(threadID: thread.id))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            ZStack(alignment: .trailing) {
                Group {
                    if isAwaitingInput {
                        Text("Pending")
                            .font(sidebarMetaFont.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(compactRelativeAge(from: thread.updatedAt))
                            .font(sidebarMetaFont)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: SidebarLayoutSpec.threadMetaColumnWidth, alignment: .trailing)
                .opacity(isHovered ? 0 : 1)
                .allowsHitTesting(false)

                HStack(spacing: SidebarLayoutSpec.threadControlSlotSpacing) {
                    Button {
                        model.togglePin(threadID: thread.id)
                    } label: {
                        Image(systemName: thread.isPinned ? "star.fill" : "star")
                            .font(sidebarMetaIconFont)
                            .foregroundStyle(
                                thread.isPinned
                                    ? Color(hex: tokens.palette.accentHex).opacity(0.9)
                                    : .secondary
                            )
                            .frame(width: SidebarLayoutSpec.controlButtonSize, height: SidebarLayoutSpec.controlButtonSize)
                    }
                    .buttonStyle(.plain)
                    .help(thread.isPinned ? "Remove star" : "Star chat")
                    .accessibilityLabel(thread.isPinned ? "Remove star from \(thread.title)" : "Star \(thread.title)")

                    Button {
                        suppressThreadSelectionInteraction()
                        hoveredThreadID = nil
                        model.archiveThread(threadID: thread.id)
                    } label: {
                        Image(systemName: "archivebox")
                            .font(sidebarMetaIconFont)
                            .foregroundStyle(.secondary)
                            .frame(width: SidebarLayoutSpec.controlButtonSize, height: SidebarLayoutSpec.controlButtonSize)
                    }
                    .buttonStyle(.plain)
                    .help("Archive chat")
                    .accessibilityLabel("Archive \(thread.title)")
                }
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
            .frame(width: SidebarLayoutSpec.threadTrailingWidth, alignment: .trailing)
            .padding(.trailing, SidebarLayoutSpec.rowHorizontalPadding)
        }
        .padding(.horizontal, SidebarLayoutSpec.selectedRowInset)
        .frame(maxWidth: .infinity, minHeight: SidebarLayoutSpec.rowMinHeight, alignment: .leading)
        .onHover { hovering in
            guard !isThreadSelectionSuppressed else {
                hoveredThreadID = nil
                return
            }
            let nextHoveredID = hovering ? thread.id : nil
            guard hoveredThreadID != nextHoveredID else {
                return
            }
            hoveredThreadID = nextHoveredID
        }
    }

    @ViewBuilder
    private func threadStatusMarker(for threadID: UUID) -> some View {
        if model.hasPendingApproval(for: threadID) {
            Image(systemName: "questionmark.circle.fill")
                .font(sidebarMetaIconFont)
                .foregroundStyle(Color(hex: tokens.palette.accentHex).opacity(0.9))
                .frame(width: SidebarLayoutSpec.iconColumnWidth, alignment: .leading)
                .accessibilityLabel("Awaiting input")
        } else if model.isThreadWorking(threadID) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.72)
                .frame(width: SidebarLayoutSpec.iconColumnWidth, alignment: .leading)
                .accessibilityLabel("Working")
        } else if model.isThreadUnread(threadID) {
            Circle()
                .fill(Color(hex: tokens.palette.accentHex).opacity(0.9))
                .frame(width: 8, height: 8)
                .frame(width: SidebarLayoutSpec.iconColumnWidth, alignment: .leading)
                .accessibilityLabel("Unread updates")
        } else {
            Color.clear
                .frame(width: SidebarLayoutSpec.iconColumnWidth, height: 8, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    private func threadStatusHint(threadID: UUID) -> String {
        if model.hasPendingApproval(for: threadID) {
            return "This chat is awaiting your approval input."
        }
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
                .buttonStyle(SidebarRowButtonStyle(cornerRadius: SidebarLayoutSpec.selectedRowCornerRadius))
                .padding(.horizontal, SidebarLayoutSpec.selectedRowInset)
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
                        .font(sidebarMetaIconFont)
                        .frame(width: SidebarLayoutSpec.controlButtonSize, height: SidebarLayoutSpec.controlButtonSize)
                }
                .frame(minHeight: SidebarLayoutSpec.footerHeight - (SidebarLayoutSpec.footerVerticalInset * 2))
                .padding(.horizontal, SidebarLayoutSpec.footerHorizontalInset)
                .padding(.vertical, SidebarLayoutSpec.footerVerticalInset)
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

    private func suppressThreadSelectionInteraction(for duration: TimeInterval = 0.24) {
        threadSelectionSuppressionGeneration += 1
        let generation = threadSelectionSuppressionGeneration
        isThreadSelectionSuppressed = true

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard threadSelectionSuppressionGeneration == generation else {
                return
            }
            isThreadSelectionSuppressed = false
        }
    }

    private var searchFieldFillColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.10)
        }
        return Color.black.opacity(0.04)
    }

    private var searchFieldBorderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.12)
        }
        return Color.black.opacity(0.07)
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
    let iconTextGap: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minimumHeight: CGFloat
    let bodyFont: Font
    let iconFont: Font
    let cornerRadius: CGFloat
    let horizontalInset: CGFloat
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        icon: String,
        title: String,
        iconColumnWidth: CGFloat,
        iconTextGap: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        minimumHeight: CGFloat,
        bodyFont: Font,
        iconFont: Font,
        cornerRadius: CGFloat,
        horizontalInset: CGFloat,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.iconColumnWidth = iconColumnWidth
        self.iconTextGap = iconTextGap
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.minimumHeight = minimumHeight
        self.bodyFont = bodyFont
        self.iconFont = iconFont
        self.cornerRadius = cornerRadius
        self.horizontalInset = horizontalInset
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
            HStack(spacing: iconTextGap) {
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
            cornerRadius: cornerRadius,
            isHovered: isHovered
        ))
        .padding(.horizontal, horizontalInset)
        .onHover { hovering in
            guard isHovered != hovering else {
                return
            }
            isHovered = hovering
        }
    }
}
