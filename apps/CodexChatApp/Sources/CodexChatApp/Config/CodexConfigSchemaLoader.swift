import Foundation

struct CodexConfigSchemaPayload: Sendable {
    let data: Data
    let source: CodexConfigSchemaSource
}

enum CodexConfigSchemaLoaderError: LocalizedError {
    case missingBundledSchema
    case invalidSchema(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledSchema:
            "Bundled Codex config schema is missing."
        case let .invalidSchema(detail):
            "Codex config schema is invalid: \(detail)"
        }
    }
}

struct CodexConfigSchemaLoader {
    let remoteURL: URL
    let cacheURL: URL
    let bundledSchemaURL: URL?
    let fileManager: FileManager

    init(
        remoteURL: URL = URL(string: "https://developers.openai.com/codex/config-schema.json")!,
        cacheURL: URL,
        bundledSchemaURL: URL?,
        fileManager: FileManager = .default
    ) {
        self.remoteURL = remoteURL
        self.cacheURL = cacheURL
        self.bundledSchemaURL = bundledSchemaURL
        self.fileManager = fileManager
    }

    @MainActor
    func load() async throws -> CodexConfigSchemaPayload {
        if let remote = try await fetchRemoteSchema() {
            return remote
        }

        if let cached = try loadCachedSchema() {
            return cached
        }

        guard let bundledSchemaURL else {
            throw CodexConfigSchemaLoaderError.missingBundledSchema
        }

        let data = try Data(contentsOf: bundledSchemaURL)
        try validateSchemaData(data)
        return CodexConfigSchemaPayload(data: data, source: .bundled)
    }

    @MainActor
    private func fetchRemoteSchema() async throws -> CodexConfigSchemaPayload? {
        var request = URLRequest(url: remoteURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
                return nil
            }

            try validateSchemaData(data)
            try cacheSchemaData(data)
            return CodexConfigSchemaPayload(data: data, source: .remote)
        } catch {
            return nil
        }
    }

    @MainActor
    private func loadCachedSchema() throws -> CodexConfigSchemaPayload? {
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: cacheURL)
        try validateSchemaData(data)
        return CodexConfigSchemaPayload(data: data, source: .cache)
    }

    @MainActor
    private func cacheSchemaData(_ data: Data) throws {
        try fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: [.atomic])
    }

    @MainActor
    private func validateSchemaData(_ data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any], object["properties"] != nil else {
            throw CodexConfigSchemaLoaderError.invalidSchema("Missing root properties object")
        }
    }
}
