import AppKit
import Foundation

extension AppModel {
    func toggleDiagnostics() {
        isDiagnosticsVisible.toggle()
        appendLog(.debug, "Diagnostics toggled: \(isDiagnosticsVisible)")
    }

    func closeDiagnostics() {
        isDiagnosticsVisible = false
    }

    func copyDiagnosticsBundle() {
        do {
            let snapshot = DiagnosticsBundleSnapshot(
                generatedAt: Date(),
                runtimeStatus: runtimeStatus,
                runtimeIssue: runtimeIssue?.message,
                accountSummary: accountSummaryText,
                logs: logs
            )
            let bundleURL = try DiagnosticsBundleExporter.export(snapshot: snapshot)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bundleURL.path, forType: .string)
            accountStatusMessage = "Diagnostics bundle created and copied: \(bundleURL.lastPathComponent)"
            appendLog(.info, "Diagnostics bundle exported")
        } catch DiagnosticsBundleExporterError.cancelled {
            appendLog(.debug, "Diagnostics export cancelled")
        } catch {
            accountStatusMessage = "Failed to export diagnostics: \(error.localizedDescription)"
            appendLog(.error, "Diagnostics export failed: \(error.localizedDescription)")
        }
    }

    func copyExtensibilityDiagnostics() {
        do {
            let snapshot = ExtensibilityDiagnosticsSnapshot(
                generatedAt: Date(),
                retentionLimit: extensibilityDiagnosticsRetentionLimit,
                events: extensibilityDiagnostics
            )
            let destinationURL = try ExtensibilityDiagnosticsExporter.export(snapshot: snapshot)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(destinationURL.path, forType: .string)
            accountStatusMessage = "Extensibility diagnostics exported and copied: \(destinationURL.lastPathComponent)"
            appendLog(.info, "Extensibility diagnostics exported")
        } catch ExtensibilityDiagnosticsExporterError.cancelled {
            appendLog(.debug, "Extensibility diagnostics export cancelled")
        } catch {
            accountStatusMessage = "Failed to export extensibility diagnostics: \(error.localizedDescription)"
            appendLog(.error, "Extensibility diagnostics export failed: \(error.localizedDescription)")
        }
    }
}
