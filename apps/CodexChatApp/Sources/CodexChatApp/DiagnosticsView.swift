import CodexKit
import SwiftUI

struct DiagnosticsView: View {
    let runtimeStatus: RuntimeStatus
    let logs: [LogEntry]
    let onClose: () -> Void

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
                HStack {
                    Text("Status")
                    Spacer()
                    Text(runtimeStatus.rawValue.capitalized)
                        .foregroundStyle(.secondary)
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
}
