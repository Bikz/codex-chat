import Foundation

public enum ModScope: String, CaseIterable, Hashable, Sendable, Codable {
    case global
    case project
}

public struct UIModManifest: Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var version: String
    public var author: String?
    public var license: String?
    public var description: String?
    public var homepage: String?
    public var repository: String?
    public var checksum: String?

    public init(
        id: String,
        name: String,
        version: String,
        author: String? = nil,
        license: String? = nil,
        description: String? = nil,
        homepage: String? = nil,
        repository: String? = nil,
        checksum: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.license = license
        self.description = description
        self.homepage = homepage
        self.repository = repository
        self.checksum = checksum
    }
}

public struct UIModDefinition: Hashable, Sendable, Codable {
    public struct Future: Hashable, Sendable, Codable {
        public struct OptionalPane: Hashable, Sendable, Codable {
            public var inspectorSurfaceHint: String?

            public init(inspectorSurfaceHint: String? = nil) {
                self.inspectorSurfaceHint = inspectorSurfaceHint
            }
        }

        public var optionalPane: OptionalPane?

        public init(optionalPane: OptionalPane? = nil) {
            self.optionalPane = optionalPane
        }
    }

    public var schemaVersion: Int
    public var manifest: UIModManifest
    public var theme: ModThemeOverride
    public var future: Future?

    public init(schemaVersion: Int = 1, manifest: UIModManifest, theme: ModThemeOverride, future: Future? = nil) {
        self.schemaVersion = schemaVersion
        self.manifest = manifest
        self.theme = theme
        self.future = future
    }
}

public struct DiscoveredUIMod: Identifiable, Hashable, Sendable {
    public let id: String
    public let scope: ModScope
    public let directoryPath: String
    public let definitionPath: String
    public let definition: UIModDefinition
    public let computedChecksum: String?

    public init(scope: ModScope, directoryPath: String, definitionPath: String, definition: UIModDefinition, computedChecksum: String?) {
        self.id = "\(scope.rawValue):\(directoryPath)"
        self.scope = scope
        self.directoryPath = directoryPath
        self.definitionPath = definitionPath
        self.definition = definition
        self.computedChecksum = computedChecksum
    }
}

public enum UIModDiscoveryError: LocalizedError, Sendable {
    case missingManifest(String)
    case invalidManifestID(String)
    case invalidSchemaVersion(Int)
    case unreadableDefinition(String)
    case invalidChecksum(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .missingManifest(let path):
            return "Missing mod manifest in \(path)"
        case .invalidManifestID(let id):
            return "Mod manifest id is invalid: \(id)"
        case .invalidSchemaVersion(let version):
            return "Unsupported mod schema version: \(version)"
        case .unreadableDefinition(let message):
            return "Failed to load mod definition: \(message)"
        case .invalidChecksum(let expected, let actual):
            return "Mod checksum mismatch (expected \(expected), got \(actual))"
        }
    }
}

