import Foundation

public struct LaunchdJobSpec: Hashable, Sendable {
    public var label: String
    public var programArguments: [String]
    public var workingDirectory: String?
    public var standardOutPath: String?
    public var standardErrorPath: String?
    public var startIntervalSeconds: Int

    public init(
        label: String,
        programArguments: [String],
        workingDirectory: String? = nil,
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil,
        startIntervalSeconds: Int
    ) {
        self.label = label
        self.programArguments = programArguments
        self.workingDirectory = workingDirectory
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.startIntervalSeconds = startIntervalSeconds
    }
}

public enum LaunchdManagerError: LocalizedError, Sendable {
    case plistEncodingFailed
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .plistEncodingFailed:
            "Failed to encode launchd plist."
        case let .commandFailed(message):
            message
        }
    }
}

public struct LaunchdManager {
    public init() {}

    public func plistData(for spec: LaunchdJobSpec) throws -> Data {
        var dictionary: [String: Any] = [
            "Label": spec.label,
            "ProgramArguments": spec.programArguments,
            "RunAtLoad": false,
            "StartInterval": max(60, spec.startIntervalSeconds),
        ]

        if let workingDirectory = spec.workingDirectory, !workingDirectory.isEmpty {
            dictionary["WorkingDirectory"] = workingDirectory
        }
        if let standardOutPath = spec.standardOutPath, !standardOutPath.isEmpty {
            dictionary["StandardOutPath"] = standardOutPath
        }
        if let standardErrorPath = spec.standardErrorPath, !standardErrorPath.isEmpty {
            dictionary["StandardErrorPath"] = standardErrorPath
        }

        guard PropertyListSerialization.propertyList(dictionary, isValidFor: .xml) else {
            throw LaunchdManagerError.plistEncodingFailed
        }

        return try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
    }

    public func writePlist(spec: LaunchdJobSpec, directoryURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let plistURL = directoryURL.appendingPathComponent("\(spec.label).plist", isDirectory: false)
        let data = try plistData(for: spec)
        try data.write(to: plistURL, options: [.atomic])
        return plistURL
    }

    public func bootstrap(plistURL: URL, uid: uid_t) throws {
        let output = try runLaunchctl(arguments: ["bootstrap", "gui/\(uid)", plistURL.path])
        if !output.isEmpty {
            _ = output
        }
    }

    public func bootout(label: String, uid: uid_t) throws {
        _ = try runLaunchctl(arguments: ["bootout", "gui/\(uid)/\(label)"])
    }

    @discardableResult
    private func runLaunchctl(arguments: [String]) throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchdManagerError.commandFailed(
                "launchctl \(arguments.joined(separator: " ")) failed (\(process.terminationStatus)): \(detail)"
            )
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
