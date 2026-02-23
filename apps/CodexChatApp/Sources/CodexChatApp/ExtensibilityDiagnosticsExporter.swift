import AppKit
import Foundation
import UniformTypeIdentifiers

enum ExtensibilityDiagnosticsExporterError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Extensibility diagnostics export cancelled"
        }
    }
}

struct ExtensibilityDiagnosticsSnapshot: Codable {
    let generatedAt: Date
    let retentionLimit: Int
    let events: [AppModel.ExtensibilityDiagnosticEvent]
}

enum ExtensibilityDiagnosticsExporter {
    @MainActor
    static func export(snapshot: ExtensibilityDiagnosticsSnapshot) throws -> URL {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.title = "Export Extensibility Diagnostics"
        savePanel.nameFieldStringValue = "codexchat-extensibility-diagnostics-\(timestampString(Date())).json"
        savePanel.allowedContentTypes = [.json]

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            throw ExtensibilityDiagnosticsExporterError.cancelled
        }

        let data = try payloadData(snapshot: snapshot)
        try data.write(to: destinationURL, options: [.atomic])
        return destinationURL
    }

    static func payloadData(snapshot: ExtensibilityDiagnosticsSnapshot) throws -> Data {
        try JSONEncoder.prettyExtensibility.encode(snapshot)
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

private extension JSONEncoder {
    static var prettyExtensibility: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
