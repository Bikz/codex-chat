import Foundation

enum ChatTitleGenerator {
    static let model = "gpt-4o-mini"
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    static func generateTitle(userText: String, apiKey: String) async throws -> String? {
        let trimmedUserText = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserText.isEmpty, !trimmedAPIKey.isEmpty else {
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")

        let prompt = """
        Write a concise chat title for this user request.
        Rules:
        - 2 to 5 words.
        - Plain text only.
        - No quotes.
        - No trailing punctuation.
        User request:
        \(trimmedUserText)
        """

        let payload: [String: Any] = [
            "model": model,
            "input": prompt,
            "max_output_tokens": 20,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            return nil
        }

        guard let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let rawTitle = extractRawTitle(from: object)
        else {
            return nil
        }

        return normalizedTitle(rawTitle)
    }

    static func extractRawTitle(from response: [String: Any]) -> String? {
        if let outputText = response["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return outputText
        }

        guard let outputItems = response["output"] as? [[String: Any]] else {
            return nil
        }

        for item in outputItems {
            guard let contentItems = item["content"] as? [[String: Any]] else {
                continue
            }

            for content in contentItems {
                if let text = content["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    return text
                }
                if let fallbackText = content["output_text"] as? String,
                   !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    return fallbackText
                }
            }
        }

        return nil
    }

    static func normalizedTitle(_ rawTitle: String) -> String? {
        var normalized = rawTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let wrappers: [(Character, Character)] = [
            ("\"", "\""),
            ("'", "'"),
            ("`", "`"),
            ("“", "”"),
        ]
        for (opening, closing) in wrappers {
            if normalized.first == opening, normalized.last == closing, normalized.count >= 2 {
                normalized.removeFirst()
                normalized.removeLast()
                normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        normalized = normalized
            .replacingOccurrences(of: "[\\.:;!?,]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return nil
        }

        var words = normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard words.count >= 2 else {
            return nil
        }

        if words.count > 5 {
            words = Array(words.prefix(5))
        }

        let joined = words.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
