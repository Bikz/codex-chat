import Foundation

public struct CatalogModListing: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String?
    public let license: String?
    public let summary: String?
    public let repositoryURL: String?
    public let downloadURL: String?
    public let checksum: String?
    public let rankingScore: Double?
    public let trustMetadata: String?

    public init(
        id: String,
        name: String,
        version: String,
        author: String? = nil,
        license: String? = nil,
        summary: String? = nil,
        repositoryURL: String? = nil,
        downloadURL: String? = nil,
        checksum: String? = nil,
        rankingScore: Double? = nil,
        trustMetadata: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.license = license
        self.summary = summary
        self.repositoryURL = repositoryURL
        self.downloadURL = downloadURL
        self.checksum = checksum
        self.rankingScore = rankingScore
        self.trustMetadata = trustMetadata
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

public struct RemoteJSONModCatalogProvider: ModCatalogProvider {
    public let indexURL: URL
    public let urlSession: URLSession

    private struct WrappedIndex: Codable {
        var mods: [CatalogModListing]
    }

    public init(indexURL: URL, urlSession: URLSession = .shared) {
        self.indexURL = indexURL
        self.urlSession = urlSession
    }

    public func listAvailableMods() async throws -> [CatalogModListing] {
        let (data, response) = try await urlSession.data(from: indexURL)
        if let response = response as? HTTPURLResponse,
           !(200 ... 299).contains(response.statusCode)
        {
            throw NSError(
                domain: "CodexMods.RemoteCatalog",
                code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Catalog request failed with status \(response.statusCode)."]
            )
        }

        let decoder = JSONDecoder()
        let direct = try? decoder.decode([CatalogModListing].self, from: data)
        let wrapped = try? decoder.decode(WrappedIndex.self, from: data)
        let listings = direct ?? wrapped?.mods ?? []

        return listings.sorted {
            let lhs = $0.rankingScore ?? -Double.greatestFiniteMagnitude
            let rhs = $1.rankingScore ?? -Double.greatestFiniteMagnitude
            if lhs == rhs {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return lhs > rhs
        }
    }
}
