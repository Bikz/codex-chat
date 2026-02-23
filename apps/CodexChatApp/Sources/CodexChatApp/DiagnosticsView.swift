import AppKit
import CodexKit
import SwiftUI

struct DiagnosticsView: View {
    let runtimeStatus: RuntimeStatus
    let runtimePoolSnapshot: RuntimePoolSnapshot
    let adaptiveTurnConcurrencyLimit: Int
    let logs: [LogEntry]
    let extensibilityDiagnostics: [AppModel.ExtensibilityDiagnosticEvent]
    let onClose: () -> Void
    @State private var performanceSnapshot = PerformanceSnapshot(
        generatedAt: .distantPast,
        operations: [],
        recent: []
    )
    @State private var refreshTask: Task<Void, Never>?

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
                    HStack {
                        Text("Adaptive turn limit")
                        Spacer()
                        Text("\(adaptiveTurnConcurrencyLimit)")
                            .foregroundStyle(.secondary)
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
                                        Button("Copy rerun command") {
                                            copyToPasteboard(suggestedCommand)
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
}
