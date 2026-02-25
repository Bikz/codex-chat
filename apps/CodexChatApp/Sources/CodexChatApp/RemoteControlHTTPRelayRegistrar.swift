import CodexChatRemoteControl
import Foundation

actor RemoteControlHTTPRelayRegistrar: RemoteControlRelayRegistering {
    private let urlSession: URLSession
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonDecoder.dateDecodingStrategy = .iso8601
    }

    func startPairing(_ request: RemoteControlPairStartRequest) async throws -> RemoteControlPairStartResponse {
        let relayWebSocketURL = try parsedRelayWebSocketURL(from: request.relayWebSocketURL)
        let endpointURL = try pairStartEndpointURL(from: relayWebSocketURL)

        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 15
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let details = String(data: data, encoding: .utf8) ?? "Unexpected relay response"
            throw NSError(
                domain: "CodexChat.RemoteControlRelay",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: details]
            )
        }

        let decoded = try jsonDecoder.decode(RelayPairStartResponse.self, from: data)
        return RemoteControlPairStartResponse(
            accepted: decoded.accepted,
            relayWebSocketURL: decoded.wsURL
        )
    }

    private func parsedRelayWebSocketURL(from rawValue: String) throws -> URL {
        guard let url = URL(string: rawValue) else {
            throw URLError(.badURL)
        }
        return url
    }

    private func pairStartEndpointURL(from relayWebSocketURL: URL) throws -> URL {
        guard var components = URLComponents(url: relayWebSocketURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        if components.scheme == "wss" {
            components.scheme = "https"
        } else if components.scheme == "ws" {
            components.scheme = "http"
        }

        components.path = "/pair/start"
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }
}

private struct RelayPairStartResponse: Decodable {
    let accepted: Bool
    let wsURL: String?
}
