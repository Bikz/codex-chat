import CodexChatCore
import Foundation

struct PlanRunnerCapabilityEvaluation: Hashable, Sendable {
    let requiredCapabilities: Set<PlanRunnerCapability>
    let undeclaredCapabilities: Set<PlanRunnerCapability>
    let blockedForTrustState: Set<PlanRunnerCapability>
}

enum PlanRunnerCapabilityPolicy {
    private static let privilegedCapabilities: Set<PlanRunnerCapability> = [
        .nativeActions,
        .filesystemWrite,
        .network,
        .runtimeControl,
    ]

    static func evaluate(document: PlanDocument, trustState: ProjectTrustState) -> PlanRunnerCapabilityEvaluation {
        let required = requiredCapabilities(for: document)
        let undeclared = required.subtracting(document.requestedCapabilities)
        let blocked = trustState == .untrusted
            ? required.intersection(privilegedCapabilities)
            : []
        return PlanRunnerCapabilityEvaluation(
            requiredCapabilities: required,
            undeclaredCapabilities: undeclared,
            blockedForTrustState: blocked
        )
    }

    static func requiredCapabilities(for document: PlanDocument) -> Set<PlanRunnerCapability> {
        var required = Set<PlanRunnerCapability>()
        for task in document.tasks {
            let normalized = task.title.lowercased()
            if containsAny(
                normalized,
                substrings: [
                    "native action",
                    "native.action",
                    "calendar.",
                    "messages.",
                    "desktop.cleanup",
                    "reminders.",
                    "applescript",
                    "apple script",
                    "jxa",
                    "harness invoke",
                ]
            ) {
                required.insert(.nativeActions)
            }

            if containsAny(
                normalized,
                substrings: [
                    "write file",
                    "create file",
                    "modify file",
                    "delete file",
                    "rename file",
                    "move file",
                    "patch file",
                    "filesystem",
                    "project write",
                ]
            ) {
                required.insert(.filesystemWrite)
            }

            if containsAny(
                normalized,
                substrings: [
                    "http://",
                    "https://",
                    "api call",
                    "web request",
                    "network request",
                    "fetch ",
                ]
            ) {
                required.insert(.network)
            }

            if containsAny(
                normalized,
                substrings: [
                    "restart runtime",
                    "runtime control",
                    "reset runtime",
                ]
            ) {
                required.insert(.runtimeControl)
            }
        }
        return required
    }

    private static func containsAny(_ text: String, substrings: [String]) -> Bool {
        substrings.contains(where: { text.contains($0) })
    }
}
