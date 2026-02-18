import Foundation

public struct CatalogModListing: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String?
    public let license: String?
    public let summary: String?
    public let downloadURL: String?
    public let checksum: String?

    public init(
        id: String,
        name: String,
        version: String,
        author: String? = nil,
        license: String? = nil,
        summary: String? = nil,
        downloadURL: String? = nil,
        checksum: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.license = license
        self.summary = summary
        self.downloadURL = downloadURL
        self.checksum = checksum
    }
}

public protocol ModCatalogProvider: Sendable {
    func listAvailableMods() async throws -> [CatalogModListing]
}

public struct EmptyModCatalogProvider: ModCatalogProvider {
    public init() {}

    public func listAvailableMods() async throws -> [CatalogModListing] {
        []
    }
}

