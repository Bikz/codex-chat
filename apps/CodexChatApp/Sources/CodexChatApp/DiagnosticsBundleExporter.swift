import AppKit
import CodexKit
import Foundation
import UniformTypeIdentifiers

enum DiagnosticsBundleExporterError: LocalizedError {
    case cancelled
    case zipFailed(code: Int32)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Diagnostics export cancelled"
        case .zipFailed(let code):
            return "Could not create diagnostics archive (zip exited with code \(code))"
        }
    }
}

struct DiagnosticsBundleSnapshot: Codable {
    let generatedAt: Date
    let runtimeStatus: RuntimeStatus
    let runtimeIssue: String?
    let accountSummary: String
    let logs: [LogEntry]
}

enum DiagnosticsBundleExporter {
    @MainActor
    static func export(snapshot: DiagnosticsBundleSnapshot) throws -> URL {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.title = "Export Diagnostics Bundle"
        savePanel.nameFieldStringValue = "codexchat-diagnostics-\(timestampString(Date())).zip"
        savePanel.allowedContentTypes = [.zip]

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            throw DiagnosticsBundleExporterError.cancelled
        }

        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("codexchat-diagnostics-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let sanitizedSnapshot = DiagnosticsBundleSnapshot(
            generatedAt: snapshot.generatedAt,
            runtimeStatus: snapshot.runtimeStatus,
            runtimeIssue: snapshot.runtimeIssue,
            accountSummary: snapshot.accountSummary,
            logs: snapshot.logs.map { entry in
                LogEntry(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    level: entry.level,
                    message: redactSensitiveText(in: entry.message)
                )
            }
        )

        let diagnosticsURL = tempDirectory.appendingPathComponent("diagnostics.json")
        let diagnosticsData = try JSONEncoder.pretty.encode(sanitizedSnapshot)
        try diagnosticsData.write(to: diagnosticsURL, options: [.atomic])

        let logLines = sanitizedSnapshot.logs.map { entry in
            "[\(entry.timestamp.formatted(.iso8601))] \(entry.level.rawValue.uppercased()) \(entry.message)"
        }
        let logsURL = tempDirectory.appendingPathComponent("logs.txt")
        let logsData = logLines.joined(separator: "\n").data(using: .utf8) ?? Data()
        try logsData.write(to: logsURL, options: [.atomic])

        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = tempDirectory
        zip.arguments = [
            "-r",
            "-q",
            destinationURL.path,
            "diagnostics.json",
            "logs.txt"
        ]
        try zip.run()
        zip.waitUntilExit()

        guard zip.terminationStatus == 0 else {
            throw DiagnosticsBundleExporterError.zipFailed(code: zip.terminationStatus)
        }

        return destinationURL
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func redactSensitiveText(in text: String) -> String {
        var sanitized = text
        let patterns = [
            "sk-[A-Za-z0-9_-]{16,}",
            "(?i)api[_-]?key\\s*[:=]\\s*[^\\s]+",
            "(?i)authorization\\s*:\\s*bearer\\s+[^\\s]+"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(in: sanitized, range: range, withTemplate: "[REDACTED]")
        }

        return sanitized
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
