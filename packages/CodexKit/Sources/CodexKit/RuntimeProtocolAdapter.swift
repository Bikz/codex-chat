import Foundation

public struct RuntimeCompatibilityMatrix: Hashable, Sendable {
    public let validatedMinorLine: String
    public let graceMinorLine: String

    public init(validatedMinorLine: String, graceMinorLine: String) {
        self.validatedMinorLine = validatedMinorLine
        self.graceMinorLine = graceMinorLine
    }

    public static let current = RuntimeCompatibilityMatrix(
        validatedMinorLine: "0.114",
        graceMinorLine: "0.113"
    )

    public func evaluate(version: RuntimeVersionInfo?) -> RuntimeCompatibilityState {
        guard let version else {
            return RuntimeCompatibilityState(
                detectedVersion: nil,
                supportLevel: .unknown,
                supportedMinorLine: validatedMinorLine,
                graceMinorLine: graceMinorLine,
                degradedReasons: [
                    "Could not determine the installed Codex runtime version before startup.",
                ],
                disabledFeatures: RuntimeProtocolAdapter.degradedFeatures
            )
        }

        if version.minorLine == validatedMinorLine {
            return RuntimeCompatibilityState(
                detectedVersion: version,
                supportLevel: .validated,
                supportedMinorLine: validatedMinorLine,
                graceMinorLine: graceMinorLine,
                degradedReasons: [],
                disabledFeatures: []
            )
        }

        if version.minorLine == graceMinorLine {
            return RuntimeCompatibilityState(
                detectedVersion: version,
                supportLevel: .grace,
                supportedMinorLine: validatedMinorLine,
                graceMinorLine: graceMinorLine,
                degradedReasons: [
                    "CodexChat was validated against Codex \(validatedMinorLine).x. Running \(version.rawValue) in compatibility mode.",
                ],
                disabledFeatures: RuntimeProtocolAdapter.degradedFeatures
            )
        }

        return RuntimeCompatibilityState(
            detectedVersion: version,
            supportLevel: .unsupported,
            supportedMinorLine: validatedMinorLine,
            graceMinorLine: graceMinorLine,
            degradedReasons: [
                "Codex \(version.rawValue) is outside the validated compatibility window (\(validatedMinorLine).x with \(graceMinorLine).x grace support).",
            ],
            disabledFeatures: RuntimeProtocolAdapter.degradedFeatures
        )
    }
}

struct RuntimeProtocolAdapter: Hashable, Sendable {
    let name: String
    let compatibility: RuntimeCompatibilityState

    static let degradedFeatures = [
        "Dynamic tool calls",
        "Experimental protocol fields",
    ]

    var sentCapabilities: RuntimeClientCapabilities {
        RuntimeClientCapabilities(
            experimentalAPI: false,
            optOutNotificationMethods: []
        )
    }

    var initialCapabilities: RuntimeCapabilities {
        .none
    }

    func makeInitializeParams(clientInfo: RuntimeClientInfo) -> JSONValue {
        var params: [String: JSONValue] = [
            "clientInfo": .object([
                "name": .string(clientInfo.name),
                "title": .string(clientInfo.title),
                "version": .string(clientInfo.version),
            ]),
            "capabilities": .object([
                "experimentalApi": .bool(sentCapabilities.experimentalAPI),
                "optOutNotificationMethods": .array(sentCapabilities.optOutNotificationMethods.map(JSONValue.string)),
            ]),
        ]

        if compatibility.isDegraded {
            params["clientMode"] = .string("degraded")
        }

        return .object(params)
    }

    static func select(version: RuntimeVersionInfo?) -> RuntimeProtocolAdapter {
        let compatibility = RuntimeCompatibilityMatrix.current.evaluate(version: version)
        let adapterName = switch compatibility.supportLevel {
        case .validated:
            "validated-\(compatibility.supportedMinorLine)"
        case .grace:
            "grace-\(compatibility.graceMinorLine)"
        case .unsupported:
            "degraded-unsupported"
        case .unknown:
            "degraded-unknown"
        }
        return RuntimeProtocolAdapter(name: adapterName, compatibility: compatibility)
    }

    func decodeCapabilities(from initializeResult: JSONValue) -> RuntimeCapabilities {
        let capabilities = initializeResult.value(at: ["capabilities"])
        var decoded = initialCapabilities
        decoded.supportsTurnSteer = capabilities?.value(at: ["turnSteer"])?.boolValue ?? decoded.supportsTurnSteer

        let followUpCapability = capabilities?.value(at: ["followUpSuggestions"])
        decoded.supportsFollowUpSuggestions = if let boolValue = followUpCapability?.boolValue {
            boolValue
        } else if followUpCapability?.objectValue != nil {
            true
        } else {
            decoded.supportsFollowUpSuggestions
        }

        decoded.supportsServerRequestResolution = boolValue(capabilities, path: ["serverRequestResolved"], default: decoded.supportsServerRequestResolution)
        decoded.supportsTurnInterrupt = boolValue(capabilities, path: ["turnInterrupt"], default: decoded.supportsTurnInterrupt)
        decoded.supportsThreadResume = boolValue(capabilities, path: ["threadResume"], default: decoded.supportsThreadResume)
        decoded.supportsThreadFork = boolValue(capabilities, path: ["threadFork"], default: decoded.supportsThreadFork)
        decoded.supportsThreadList = boolValue(capabilities, path: ["threadList"], default: decoded.supportsThreadList)
        decoded.supportsThreadRead = boolValue(capabilities, path: ["threadRead"], default: decoded.supportsThreadRead)
        decoded.supportsPermissionsApproval = boolValue(capabilities, path: ["permissionsApproval"], default: decoded.supportsPermissionsApproval)
        decoded.supportsUserInputRequests = boolValue(capabilities, path: ["requestUserInput"], default: decoded.supportsUserInputRequests)
        decoded.supportsMCPElicitationRequests = boolValue(capabilities, path: ["mcpElicitation"], default: decoded.supportsMCPElicitationRequests)
        decoded.supportsDynamicToolCallRequests = boolValue(capabilities, path: ["dynamicToolCall"], default: decoded.supportsDynamicToolCallRequests)
        decoded.supportsPlanUpdates = boolValue(capabilities, path: ["turnPlanUpdates"], default: decoded.supportsPlanUpdates)
        decoded.supportsDiffUpdates = boolValue(capabilities, path: ["turnDiffUpdates"], default: decoded.supportsDiffUpdates)
        decoded.supportsTokenUsageUpdates = boolValue(capabilities, path: ["tokenUsageUpdates"], default: decoded.supportsTokenUsageUpdates)
        decoded.supportsModelReroutes = boolValue(capabilities, path: ["modelReroutes"], default: decoded.supportsModelReroutes)
        return decoded
    }

    private func boolValue(_ capabilities: JSONValue?, path: [String], default defaultValue: Bool) -> Bool {
        capabilities?.value(at: path)?.boolValue ?? defaultValue
    }
}

extension RuntimeVersionInfo {
    static func parse(from rawVersionOutput: String?) -> RuntimeVersionInfo? {
        guard let rawVersionOutput else {
            return nil
        }

        let trimmed = rawVersionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let pattern = "(\\d+)\\.(\\d+)\\.(\\d+)(?:[-+]([A-Za-z0-9.-]+))?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range) else {
            return nil
        }

        func capture(_ index: Int) -> String? {
            let captureRange = match.range(at: index)
            guard captureRange.location != NSNotFound,
                  let range = Range(captureRange, in: trimmed)
            else {
                return nil
            }
            return String(trimmed[range])
        }

        guard
            let majorText = capture(1),
            let minorText = capture(2),
            let patchText = capture(3),
            let major = Int(majorText),
            let minor = Int(minorText),
            let patch = Int(patchText)
        else {
            return nil
        }

        return RuntimeVersionInfo(
            rawValue: "\(major).\(minor).\(patch)\(capture(4).map { "-\($0)" } ?? "")",
            major: major,
            minor: minor,
            patch: patch,
            prerelease: capture(4)
        )
    }
}
