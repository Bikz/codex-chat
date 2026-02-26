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
        let endpointURL = try pairEndpointURL(from: relayWebSocketURL, path: "/pair/start")

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

    func stopPairing(_ request: RemoteControlPairStopRequest) async throws -> RemoteControlPairStopResponse {
        let relayWebSocketURL = try parsedRelayWebSocketURL(from: request.relayWebSocketURL)
        let endpointURL = try pairEndpointURL(from: relayWebSocketURL, path: "/pair/stop")

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

        let decoded = try jsonDecoder.decode(RelayPairStopResponse.self, from: data)
        return RemoteControlPairStopResponse(accepted: decoded.accepted)
    }

    private func parsedRelayWebSocketURL(from rawValue: String) throws -> URL {
        guard let url = URL(string: rawValue) else {
            throw URLError(.badURL)
        }
        return url
    }

    private func pairEndpointURL(from relayWebSocketURL: URL, path: String) throws -> URL {
        guard var components = URLComponents(url: relayWebSocketURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        if components.scheme == "wss" {
            components.scheme = "https"
        } else if components.scheme == "ws" {
            components.scheme = "http"
        }

        components.path = path
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

private struct RelayPairStopResponse: Decodable {
    let accepted: Bool
}
