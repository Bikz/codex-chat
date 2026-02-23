import CodexChatCore
import Foundation

enum ExtensibilityCapability: String, Hashable, Sendable {
    case projectRead = "project-read"
    case projectWrite = "project-write"
    case network = "network"
    case runtimeControl = "runtime-control"
    case runWhenAppClosed = "run-when-app-closed"
    case nativeActions = "native-actions"
    case filesystemWrite = "filesystem-write"
}

enum ExtensibilityCapabilityPolicy {
    private static let privilegedWhenUntrusted: Set<ExtensibilityCapability> = [
        .nativeActions,
        .filesystemWrite,
        .network,
        .runtimeControl,
    ]

    static func blockedCapabilities(
        for requiredCapabilities: Set<ExtensibilityCapability>,
        trustState: ProjectTrustState
    ) -> Set<ExtensibilityCapability> {
        guard trustState == .untrusted else {
            return []
        }
        return requiredCapabilities.intersection(privilegedWhenUntrusted)
    }

    static func planRunnerCapability(_ capability: PlanRunnerCapability) -> ExtensibilityCapability {
        switch capability {
        case .nativeActions:
            .nativeActions
        case .filesystemWrite:
            .filesystemWrite
        case .network:
            .network
        case .runtimeControl:
            .runtimeControl
        }
    }

    static func planRunnerCapabilities(_ capabilities: Set<PlanRunnerCapability>) -> Set<ExtensibilityCapability> {
        Set(capabilities.map(planRunnerCapability))
    }
}
