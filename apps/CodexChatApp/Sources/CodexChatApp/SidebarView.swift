import AppKit
import CodexChatCore
import CodexChatUI
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.designTokens) private var tokens
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings
    @AppStorage(AccountDisplayNamePreference.key) private var preferredAccountDisplayName = ""
    @FocusState private var isSearchFocused: Bool

    @State private var hoveredProjectID: UUID?
    @State private var flashedProjectID: UUID?
    @State private var hoveredThreadID: UUID?
    @State private var isSeeMoreHovered = false
    @State private var isThreadSelectionSuppressed = false
    @State private var threadSelectionSuppressionGeneration = 0
    @State private var expandedProjectThreadsByProjectID: [UUID: [ThreadRecord]] = [:]
    @State private var projectThreadLoadInFlightIDs: Set<UUID> = []

    private let projectsPreviewCount = 3

    private var sidebarBodyFont: Font {
        .system(size: 14, weight: .regular)
    }

    private var sidebarMetaFont: Font {
        .system(size: 12, weight: .regular)
    }

    private var sidebarActionFont: Font {
        .system(size: 13.5, weight: .regular)
    }

    private var sidebarSectionFont: Font {
        .system(size: 11.5, weight: .semibold)
    }

    private var sidebarBodyIconFont: Font {
        .system(size: 14, weight: .medium)
    }

    private var sidebarActionIconFont: Font {
        .system(size: 13.5, weight: .regular)
    }

    private var sidebarMetaIconFont: Font {
        .system(size: SidebarLayoutSpec.controlIconFontSize, weight: .semibold)
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        let sidebarHex = tokens.palette.sidebarHex
        if model.userThemeCustomization.isEnabled {
            ZStack {
                Color(hex: sidebarHex)
                LinearGradient(
                    colors: [Color(hex: sidebarHex), Color(hex: model.userThemeCustomization.sidebarGradientHex)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(model.userThemeCustomization.gradientStrength)
            }
        } else {
            Color(hex: sidebarHex)
        }
    }

    private var sidebarBodyIconColor: Color {
        if colorScheme == .dark {
            return Color.primary.opacity(0.84)
        }
        return Color.primary.opacity(0.74)
    }

    private var sidebarControlIconColor: Color {
        if colorScheme == .dark {
            return Color.primary.opacity(0.90)
        }
        return Color.primary.opacity(0.76)
    }

    private var sidebarAccountDisplayName: String {
        AccountDisplayNamePreference.resolvedDisplayName(
            preferredName: preferredAccountDisplayName,
            fallback: model.accountDisplayName
        )
    }

    var body: some View {
        List {
            Section {
                searchField

                if !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                    bodyFont: sidebarActionFont,
                    iconFont: sidebarActionIconFont,
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
                    bodyFont: sidebarActionFont,
                    iconFont: sidebarActionIconFont,
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
        .environment(\.defaultMinListHeaderHeight, 18)
        .scrollContentBackground(.hidden)
        .background(sidebarBackground)
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
                .foregroundStyle(sidebarBodyIconColor)
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
            .focusEffectDisabled()
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

            if model.expandedProjectIDs.contains(project.id) {
                projectThreadRows(for: project)
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
                        .foregroundStyle(sidebarControlIconColor)
                        .frame(width: SidebarLayoutSpec.iconColumnWidth, alignment: .leading)
                    Text(model.showAllProjects ? "Show less" : "See more")
                        .font(sidebarMetaFont)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, SidebarLayoutSpec.rowHorizontalPadding)
                .padding(.vertical, SidebarLayoutSpec.rowVerticalPadding)
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
                var isExpandedAfterToggle = false
                flashedProjectID = project.id
                withAnimation(.easeInOut(duration: tokens.motion.transitionDuration)) {
                    isExpandedAfterToggle = model.activateProjectFromSidebar(project.id)
                }
                if isExpandedAfterToggle {
                    loadExpandedProjectThreads(projectID: project.id)
                } else {
                    expandedProjectThreadsByProjectID.removeValue(forKey: project.id)
                    projectThreadLoadInFlightIDs.remove(project.id)
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
                        .foregroundStyle(sidebarBodyIconColor)
                        .frame(width: SidebarLayoutSpec.iconColumnWidth, alignment: .leading)

                    Text(project.name)
                        .font(sidebarBodyFont)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer(minLength: SidebarLayoutSpec.projectTextControlGap)

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
            .accessibilityHint("Starts a new draft chat and expands or collapses this project's thread list.")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            HStack(spacing: SidebarLayoutSpec.projectControlSlotSpacing) {
                Button {
                    if model.selectedProjectID != project.id {
                        model.selectProject(project.id)
                    }
                    model.createThread(in: project.id)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(sidebarMetaIconFont)
                        .foregroundStyle(sidebarControlIconColor)
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
                        .foregroundStyle(sidebarControlIconColor)
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
    private func projectThreadRows(for project: ProjectRecord) -> some View {
        if model.selectedProjectID == project.id {
            let projectThreads = model.threads.filter { $0.projectId == project.id }
            ForEach(projectThreads) { thread in
                threadRow(thread, isGeneralThread: false)
            }
        } else if let cachedThreads = expandedProjectThreadsByProjectID[project.id] {
            ForEach(cachedThreads) { thread in
                threadRow(thread, isGeneralThread: false)
            }
        } else if projectThreadLoadInFlightIDs.contains(project.id) {
            HStack(spacing: SidebarLayoutSpec.iconTextGap) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: SidebarLayoutSpec.iconColumnWidth, alignment: .leading)
                Text("Loading…")
                    .font(sidebarMetaFont)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, SidebarLayoutSpec.threadRowHorizontalPadding + SidebarLayoutSpec.selectedRowInset)
            .padding(.vertical, SidebarLayoutSpec.rowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: SidebarLayoutSpec.rowMinHeight, alignment: .leading)
        } else {
            EmptyView()
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

                    Text(thread.title)
                        .font(sidebarBodyFont)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer(minLength: SidebarLayoutSpec.threadControlSlotSpacing)

                    Color.clear
                        .frame(width: SidebarLayoutSpec.threadTrailingWidth)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, SidebarLayoutSpec.threadRowHorizontalPadding)
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
                    HStack(spacing: SidebarLayoutSpec.threadControlSlotSpacing) {
                        if model.hasPendingApproval(for: thread.id) {
                            Text("Input")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.primary.opacity(tokens.surfaces.baseOpacity * 1.2))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.primary.opacity(tokens.surfaces.hairlineOpacity))
                                )
                                .accessibilityLabel("Awaiting input")
                                .lineLimit(1)
                        } else if model.isThreadWorking(thread.id) {
                            SidebarWorkingSpinner()
                                .frame(width: SidebarLayoutSpec.controlButtonSize, height: SidebarLayoutSpec.controlButtonSize)
                                .accessibilityLabel("Working")
                        } else if model.isThreadUnread(thread.id) {
                            Circle()
                                .fill(.blue.opacity(0.9))
                                .frame(width: 8, height: 8)
                                .frame(width: SidebarLayoutSpec.controlButtonSize, height: SidebarLayoutSpec.controlButtonSize)
                                .accessibilityLabel("Unread updates")
                        } else {
                            if thread.isPinned {
                                Image(systemName: "star.fill")
                                    .font(sidebarMetaIconFont)
                                    .foregroundStyle(pinnedStarColor)
                                    .frame(width: SidebarLayoutSpec.controlButtonSize, height: SidebarLayoutSpec.controlButtonSize)
                            }

                            Text(compactRelativeAge(from: thread.updatedAt))
                                .font(sidebarMetaFont)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
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
                                    ? pinnedStarColor
                                    : sidebarControlIconColor
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
                            .foregroundStyle(sidebarControlIconColor)
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
            .padding(.trailing, SidebarLayoutSpec.threadRowHorizontalPadding)
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
            EmptyView()
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
                    UserInitialCircle(sidebarAccountDisplayName, size: 28)

                    Text(sidebarAccountDisplayName)
                        .font(sidebarBodyFont.weight(.medium))
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "gearshape")
                        .foregroundStyle(sidebarControlIconColor)
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
        .background(sidebarBackground)
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
            return Color.white.opacity(0.07)
        }
        return Color.black.opacity(0.03)
    }

    private var searchFieldBorderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.09)
        }
        return Color.black.opacity(0.05)
    }

    private var pinnedStarColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.68)
        }
        return Color.black.opacity(0.48)
    }

    private func projectLeadingIconName(isExpanded: Bool, isHovered: Bool) -> String {
        SidebarProjectIconResolver.leadingSymbolName(isExpanded: isExpanded, isHovered: isHovered)
    }

    private func loadExpandedProjectThreads(projectID: UUID) {
        guard model.selectedProjectID != projectID else {
            return
        }
        guard !projectThreadLoadInFlightIDs.contains(projectID) else {
            return
        }

        projectThreadLoadInFlightIDs.insert(projectID)
        Task {
            do {
                let threads = try await model.listThreadsForProject(projectID)
                await MainActor.run {
                    projectThreadLoadInFlightIDs.remove(projectID)
                    guard model.expandedProjectIDs.contains(projectID),
                          model.selectedProjectID != projectID
                    else {
                        return
                    }
                    expandedProjectThreadsByProjectID[projectID] = threads
                }
            } catch {
                await MainActor.run {
                    projectThreadLoadInFlightIDs.remove(projectID)
                    guard model.expandedProjectIDs.contains(projectID),
                          model.selectedProjectID != projectID
                    else {
                        return
                    }
                    expandedProjectThreadsByProjectID[projectID] = []
                }
            }
        }
    }
}

private struct SidebarWorkingSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1.5)

            Circle()
                .trim(from: 0.10, to: 0.78)
                .stroke(
                    Color.primary.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    reduceMotion
                        ? nil
                        : .linear(duration: 0.9).repeatForever(autoreverses: false),
                    value: isAnimating
                )
        }
        .frame(width: 11, height: 11)
        .onAppear {
            guard !reduceMotion else { return }
            isAnimating = true
        }
        .onChange(of: reduceMotion) { _, newValue in
            isAnimating = !newValue
        }
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
            return Color.primary.opacity(0.90)
        }
        return Color.primary.opacity(0.76)
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
