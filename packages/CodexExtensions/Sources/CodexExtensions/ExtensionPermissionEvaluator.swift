import Foundation

public enum ExtensionPermissionGrant: String, Hashable, Sendable, Codable {
    case granted
    case denied
}

public enum ExtensionPermissionDecision: Hashable, Sendable {
    case allowed
    case needsPrompt(Set<ExtensionPermissionFlag>)
    case denied(Set<ExtensionPermissionFlag>)
}

public struct ExtensionPermissionSnapshot: Hashable, Sendable {
    public var granted: Set<ExtensionPermissionFlag>
    public var denied: Set<ExtensionPermissionFlag>

    public init(granted: Set<ExtensionPermissionFlag> = [], denied: Set<ExtensionPermissionFlag> = []) {
        self.granted = granted
        self.denied = denied
    }
}

public enum ExtensionPermissionEvaluator {
    public static func evaluate(
        requested: Set<ExtensionPermissionFlag>,
        snapshot: ExtensionPermissionSnapshot
    ) -> ExtensionPermissionDecision {
        guard !requested.isEmpty else {
            return .allowed
        }

        let denied = requested.intersection(snapshot.denied)
        if !denied.isEmpty {
            return .denied(denied)
        }

        let missing = requested.subtracting(snapshot.granted)
        if missing.isEmpty {
            return .allowed
        }

        return .needsPrompt(missing)
    }
}
