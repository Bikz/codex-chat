import AppKit
import CodexKit
import SwiftUI

struct DiagnosticsView: View {
    let runtimeStatus: RuntimeStatus
    let runtimeHandshake: RuntimeHandshake?
    let runtimePoolSnapshot: RuntimePoolSnapshot
    let adaptiveTurnConcurrencyLimit: Int
    let rollingTTFTP95MS: Double?
    let approvalStatusMessage: String?
    let serverRequestStatusMessage: String?
    let pendingRuntimeRequests: [RuntimeRequestSupportSummary]
    let runtimeRequestSupportEvents: [RuntimeRequestSupportEvent]
    let logs: [LogEntry]
    let extensibilityDiagnostics: [AppModel.ExtensibilityDiagnosticEvent]
    let selectedProjectID: UUID?
    let selectedThreadID: UUID?
    let projectLabelsByID: [UUID: String]
    let threadLabelsByID: [UUID: String]
    let automationTimelineFocusFilter: AppModel.AutomationTimelineFocusFilter
    let onAutomationTimelineFocusFilterChange: @MainActor (AppModel.AutomationTimelineFocusFilter) -> Void
    let onFocusTimelineProject: @MainActor (UUID) -> Void
    let onFocusTimelineThread: @MainActor (UUID) -> Void
    let canExecuteRerunCommand: (String) -> Bool
    let rerunExecutionPolicyMessage: (String) -> String
    let onExecuteRerunCommand: (String) -> Void
    let onPrepareRerunCommand: (String) -> Void
    let onClose: () -> Void
    @State private var performanceSnapshot = PerformanceSnapshot(
        generatedAt: .distantPast,
        operations: [],
        recent: []
    )
    @State private var refreshTask: Task<Void, Never>?
    @State private var pendingAllowlistedRerunCommand: String?
    @State private var expandedAutomationRollupIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Close", action: onClose)
            }

            GroupBox("Runtime") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(runtimeStatus.rawValue.capitalized)
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top) {
                        Text("Version")
                        Spacer()
                        Text(runtimeHandshake?.runtimeVersion?.rawValue ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top) {
                        Text("Support")
                        Spacer()
                        Text(runtimeHandshake?.compatibility.supportLevel.rawValue.capitalized ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                    if let handshake = runtimeHandshake,
                       !handshake.compatibility.degradedReasons.isEmpty
                    {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Degraded reasons")
                            ForEach(handshake.compatibility.degradedReasons, id: \.self) { reason in
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Text("Adaptive turn limit")
                        Spacer()
                        Text("\(adaptiveTurnConcurrencyLimit)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Rolling TTFT p95")
                        Spacer()
                        if let rollingTTFTP95MS {
                            Text("\(rollingTTFTP95MS, specifier: "%.0f")ms")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("N/A")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let handshake = runtimeHandshake {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Negotiated capabilities")
                            Text(capabilitiesSummary(handshake.negotiatedCapabilities))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            GroupBox("Runtime Pool") {
                if runtimePoolSnapshot.configuredWorkerCount == 0 {
                    Text("Runtime pool unavailable")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Workers")
                            Spacer()
                            Text("\(runtimePoolSnapshot.activeWorkerCount)/\(runtimePoolSnapshot.configuredWorkerCount)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Pinned threads")
                            Spacer()
                            Text("\(runtimePoolSnapshot.pinnedThreadCount)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("In-flight turns")
                            Spacer()
                            Text("\(runtimePoolSnapshot.totalInFlightTurns)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Queued turns")
                            Spacer()
                            Text("\(runtimePoolSnapshot.totalQueuedTurns)")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(runtimePoolSnapshot.workers, id: \.workerID) { worker in
                            HStack {
                                Text("\(worker.workerID.description)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(worker.health.rawValue.capitalized)
                                    .font(.caption)
                                Spacer()
                                Text("inFlight \(worker.inFlightTurns)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("queued \(worker.queueDepth)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("failures \(worker.failureCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            GroupBox("Performance") {
                if performanceSnapshot.operations.isEmpty {
                    Text("No performance samples yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(performanceSnapshot.operations.prefix(12), id: \.name) { operation in
                            HStack {
                                Text(operation.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text("p95 \(operation.p95MS, specifier: "%.1f")ms")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("n=\(operation.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            GroupBox("Runtime Requests") {
                if pendingRuntimeRequests.isEmpty, runtimeRequestSupportEvents.isEmpty {
                    Text("No pending runtime requests or recent lifecycle events")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Pending count")
                            Spacer()
                            Text("\(pendingRuntimeRequests.count)")
                                .foregroundStyle(.secondary)
                        }
                        if !runtimeRequestBreakdown.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Breakdown")
                                Text(runtimeRequestBreakdown)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let approvalStatusMessage, !approvalStatusMessage.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Approval status")
                                Text(approvalStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let serverRequestStatusMessage, !serverRequestStatusMessage.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Runtime request status")
                                Text(serverRequestStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !pendingRuntimeRequests.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Pending")
                                ForEach(pendingRuntimeRequests.prefix(6)) { request in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(request.title)
                                            .font(.caption.weight(.semibold))
                                        Text(request.summary)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if !runtimeRequestSupportEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Recent events")
                                ForEach(runtimeRequestSupportEvents.prefix(8)) { event in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 8) {
                                            Text(event.timestamp.formatted(.dateTime.hour().minute().second()))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text(event.phase.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            Text(runtimeRequestKindLabel(event.kind))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(event.title)
                                            .font(.caption.weight(.semibold))
                                        Text(event.summary)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Extensibility") {
                if extensibilityDiagnostics.isEmpty {
                    Text("No extensibility diagnostics yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(extensibilityDiagnostics.prefix(8)) { event in
                            let playbook = AppModel.extensibilityDiagnosticPlaybook(for: event)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(event.timestamp.formatted(.dateTime.hour().minute().second()))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(event.surface)/\(event.operation)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(event.kind.uppercased())
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(color(forDiagnosticKind: event.kind))
                                    Spacer(minLength: 0)
                                }
                                Text(event.summary)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                                Text("Recovery: \(playbook.primaryStep)")
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 10) {
                                    Button("Copy recovery steps") {
                                        copyToPasteboard(playbook.steps.joined(separator: "\n"))
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption2)
                                    if let suggestedCommand = playbook.suggestedCommand {
                                        Button("Prepare rerun in composer") {
                                            onPrepareRerunCommand(suggestedCommand)
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption2)

                                        let canExecuteDirectly = canExecuteRerunCommand(suggestedCommand)
                                        Button(
                                            canExecuteDirectly ? "Run allowlisted rerun" : "Direct rerun blocked"
                                        ) {
                                            pendingAllowlistedRerunCommand = suggestedCommand
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption2)
                                        .disabled(!canExecuteDirectly)
                                        .help(rerunExecutionPolicyMessage(suggestedCommand))

                                        Button("Copy rerun command") {
                                            copyToPasteboard(suggestedCommand)
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption2)
                                    }
                                    if let shortcut = playbook.shortcut {
                                        Button(shortcutLabel(for: shortcut)) {
                                            performShortcut(shortcut)
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption2)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Automation Timeline") {
                Picker("Focus", selection: Binding(
                    get: { automationTimelineFocusFilter },
                    set: { nextFilter in
                        Task { @MainActor in
                            onAutomationTimelineFocusFilterChange(nextFilter)
                        }
                    }
                )) {
                    ForEach(AppModel.AutomationTimelineFocusFilter.allCases, id: \.self) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 6)

                if automationTimelineRollups.isEmpty {
                    Text(emptyAutomationTimelineMessage)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(automationTimelineRollups.prefix(8)) { rollup in
                            let event = rollup.latestEvent
                            let playbook = AppModel.extensibilityDiagnosticPlaybook(for: event)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(event.timestamp.formatted(.dateTime.hour().minute().second()))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(relativeTimestampLabel(for: event.timestamp))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(automationSourceLabel(for: event))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(event.kind.uppercased())
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(color(forDiagnosticKind: event.kind))
                                    Spacer(minLength: 0)
                                }
                                if let modID = event.modID, !modID.isEmpty {
                                    Text("Mod: \(modID)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let projectID = event.projectID {
                                    Text("Project: \(projectLabel(for: projectID))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let threadID = event.threadID {
                                    Text("Thread: \(threadLabel(for: threadID))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 10) {
                                    if let projectID = event.projectID {
                                        Button("Open project scope") {
                                            Task { @MainActor in
                                                onFocusTimelineProject(projectID)
                                            }
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption2)
                                    }
                                    if let threadID = event.threadID {
                                        Button("Open thread scope") {
                                            Task { @MainActor in
                                                onFocusTimelineThread(threadID)
                                            }
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption2)
                                    }
                                }
                                if rollup.occurrenceCount > 1 {
                                    HStack(spacing: 10) {
                                        Text(repeatedEventSummary(for: rollup))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Button(expandedAutomationRollupIDs.contains(rollup.id) ? "Hide repeats" : "Show repeats") {
                                            toggleAutomationRollupExpansion(rollup.id)
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption2)
                                    }
                                }
                                if expandedAutomationRollupIDs.contains(rollup.id), rollup.collapsedEvents.count > 1 {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(Array(rollup.collapsedEvents.dropFirst().prefix(5)), id: \.id) { repeatEvent in
                                            Text(
                                                "\(repeatEvent.timestamp.formatted(.dateTime.hour().minute().second())) - \(repeatEvent.summary)"
                                            )
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                        }
                                        if rollup.collapsedEvents.count > 6 {
                                            Text("+\(rollup.collapsedEvents.count - 6) more repeats")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                Text(event.summary)
                                    .font(.caption)
                                    .lineLimit(3)
                                    .foregroundStyle(.secondary)
                                Text("Recovery: \(playbook.primaryStep)")
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                                if !event.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Retry policy: \(rerunExecutionPolicyMessage(event.command))")
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 10) {
                                    Button("Copy recovery steps") {
                                        copyToPasteboard(playbook.steps.joined(separator: "\n"))
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption2)
                                    if let suggestedCommand = playbook.suggestedCommand {
                                        Button("Prepare rerun in composer") {
                                            onPrepareRerunCommand(suggestedCommand)
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption2)

                                        let canExecuteDirectly = canExecuteRerunCommand(suggestedCommand)
                                        Button(
                                            canExecuteDirectly ? "Run allowlisted rerun" : "Direct rerun blocked"
                                        ) {
                                            pendingAllowlistedRerunCommand = suggestedCommand
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption2)
                                        .disabled(!canExecuteDirectly)
                                        .help(rerunExecutionPolicyMessage(suggestedCommand))

                                        Button("Copy rerun command") {
                                            copyToPasteboard(suggestedCommand)
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption2)
                                    }
                                    if let shortcut = playbook.shortcut {
                                        Button(shortcutLabel(for: shortcut)) {
                                            performShortcut(shortcut)
                                        }
                                        .buttonStyle(.link)
                                        .font(.caption2)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Logs") {
                if logs.isEmpty {
                    Text("No logs yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    List(logs.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.level.rawValue.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(color(for: entry.level))
                                Spacer()
                                Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 280)
                    .listStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            startRefreshingPerformanceSnapshot()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
        .confirmationDialog(
            "Run allowlisted rerun command?",
            isPresented: Binding(
                get: { pendingAllowlistedRerunCommand != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingAllowlistedRerunCommand = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let command = pendingAllowlistedRerunCommand {
                Button("Run Now") {
                    onExecuteRerunCommand(command)
                    pendingAllowlistedRerunCommand = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAllowlistedRerunCommand = nil
            }
        } message: {
            if let command = pendingAllowlistedRerunCommand {
                Text("This queues a single allowlisted rerun request for:\n\(command)")
            }
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug:
            .secondary
        case .info:
            .blue
        case .warning:
            .orange
        case .error:
            .red
        }
    }

    private func color(forDiagnosticKind kind: String) -> Color {
        switch kind {
        case "timeout":
            .orange
        case "truncatedOutput":
            .orange
        case "launch":
            .red
        case "protocolViolation":
            .orange
        default:
            .secondary
        }
    }

    private var automationTimelineRollups: [AppModel.AutomationTimelineEventRollup] {
        let scoped = extensibilityDiagnostics.filter { event in
            if event.surface == "automations" {
                return true
            }
            if event.surface == "launchd" {
                return true
            }
            return event.surface == "extensions" && event.operation == "automation"
        }

        switch automationTimelineFocusFilter {
        case .all:
            return AppModel.rollupAutomationTimelineEvents(scoped)
        case .selectedProject:
            guard let selectedProjectID else { return [] }
            return AppModel.rollupAutomationTimelineEvents(
                scoped.filter { $0.projectID == selectedProjectID }
            )
        case .selectedThread:
            guard let selectedThreadID else { return [] }
            return AppModel.rollupAutomationTimelineEvents(
                scoped.filter { $0.threadID == selectedThreadID }
            )
        }
    }

    private var runtimeRequestBreakdown: String {
        let counts = pendingRuntimeRequests.reduce(into: [RuntimeServerRequestKind: Int]()) { partialResult, request in
            partialResult[request.kind, default: 0] += 1
        }

        return counts.keys.sorted { $0.rawValue < $1.rawValue }.map { kind in
            "\(runtimeRequestKindLabel(kind)): \(counts[kind, default: 0])"
        }.joined(separator: ", ")
    }

    private var emptyAutomationTimelineMessage: String {
        switch automationTimelineFocusFilter {
        case .all:
            "No automation diagnostics events yet"
        case .selectedProject:
            selectedProjectID == nil
                ? "Select a project to view project-scoped automation diagnostics."
                : "No automation diagnostics events for the selected project."
        case .selectedThread:
            selectedThreadID == nil
                ? "Select a thread to view thread-scoped automation diagnostics."
                : "No automation diagnostics events for the selected thread."
        }
    }

    private func automationSourceLabel(for event: AppModel.ExtensibilityDiagnosticEvent) -> String {
        switch (event.surface, event.operation) {
        case ("extensions", "automation"):
            "Scheduler"
        case ("launchd", _):
            "Launchd"
        case ("automations", "health"):
            "Health"
        default:
            "\(event.surface)/\(event.operation)"
        }
    }

    private func repeatedEventSummary(for rollup: AppModel.AutomationTimelineEventRollup) -> String {
        let seconds = Int(rollup.durationSeconds.rounded(.down))
        if seconds < 60 {
            return "Repeated \(rollup.occurrenceCount)x in the last \(max(1, seconds))s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "Repeated \(rollup.occurrenceCount)x over \(minutes)m"
        }

        let hours = minutes / 60
        return "Repeated \(rollup.occurrenceCount)x over \(hours)h"
    }

    private func runtimeRequestKindLabel(_ kind: RuntimeServerRequestKind) -> String {
        switch kind {
        case .approval:
            "Approval"
        case .permissionsApproval:
            "Permissions"
        case .userInput:
            "User input"
        case .mcpElicitation:
            "MCP"
        case .dynamicToolCall:
            "Dynamic tool"
        }
    }

    private func projectLabel(for projectID: UUID) -> String {
        if let label = projectLabelsByID[projectID], !label.isEmpty {
            return label
        }
        return projectID.uuidString
    }

    private func threadLabel(for threadID: UUID) -> String {
        if let label = threadLabelsByID[threadID], !label.isEmpty {
            return label
        }
        return threadID.uuidString
    }

    private func toggleAutomationRollupExpansion(_ rollupID: String) {
        if expandedAutomationRollupIDs.contains(rollupID) {
            expandedAutomationRollupIDs.remove(rollupID)
        } else {
            expandedAutomationRollupIDs.insert(rollupID)
        }
    }

    private func relativeTimestampLabel(for timestamp: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    private func startRefreshingPerformanceSnapshot() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                let snapshot = await PerformanceTracer.shared.snapshot()
                await MainActor.run {
                    performanceSnapshot = snapshot
                }
                try? await Task.sleep(nanoseconds: 750_000_000)
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func shortcutLabel(
        for shortcut: AppModel.ExtensibilityDiagnosticPlaybook.Shortcut
    ) -> String {
        switch shortcut {
        case .openAppSettings:
            "Open app settings"
        }
    }

    private func performShortcut(
        _ shortcut: AppModel.ExtensibilityDiagnosticPlaybook.Shortcut
    ) {
        switch shortcut {
        case .openAppSettings:
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    private func capabilitiesSummary(_ capabilities: RuntimeCapabilities) -> String {
        let enabled = [
            capabilities.supportsTurnSteer ? "turn steer" : nil,
            capabilities.supportsFollowUpSuggestions ? "follow-ups" : nil,
            capabilities.supportsServerRequestResolution ? "request resolution" : nil,
            capabilities.supportsTurnInterrupt ? "interrupt" : nil,
            capabilities.supportsThreadResume ? "thread resume" : nil,
            capabilities.supportsThreadFork ? "thread fork" : nil,
            capabilities.supportsThreadList ? "thread list" : nil,
            capabilities.supportsThreadRead ? "thread read" : nil,
            capabilities.supportsPermissionsApproval ? "permissions approvals" : nil,
            capabilities.supportsUserInputRequests ? "user input" : nil,
            capabilities.supportsMCPElicitationRequests ? "MCP elicitation" : nil,
            capabilities.supportsPlanUpdates ? "plan updates" : nil,
            capabilities.supportsDiffUpdates ? "diff updates" : nil,
            capabilities.supportsTokenUsageUpdates ? "token usage" : nil,
            capabilities.supportsModelReroutes ? "model reroutes" : nil,
        ].compactMap(\.self)

        if enabled.isEmpty {
            return "No runtime capabilities advertised."
        }

        return enabled.joined(separator: ", ")
    }
}
