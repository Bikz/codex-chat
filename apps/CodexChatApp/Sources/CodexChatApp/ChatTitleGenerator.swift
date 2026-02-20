import CodexKit
import Foundation

enum ChatTitleGenerator {
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    static func generateTitle(
        userText: String,
        apiKey: String,
        model: String,
        reasoningEffort: String?
    ) async throws -> String? {
        let trimmedUserText = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserText.isEmpty, !trimmedAPIKey.isEmpty, !trimmedModel.isEmpty else {
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")

        let payload = requestPayload(
            userText: trimmedUserText,
            model: trimmedModel,
            reasoningEffort: reasoningEffort
        )
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

    static func requestPayload(
        userText: String,
        model: String,
        reasoningEffort: String?
    ) -> [String: Any] {
        let prompt = """
        Write a concise chat title for this user request.
        Rules:
        - 2 to 5 words.
        - Plain text only.
        - No quotes.
        - No trailing punctuation.
        User request:
        \(userText)
        """

        var payload: [String: Any] = [
            "model": model,
            "input": prompt,
            "max_output_tokens": 20,
        ]

        if let reasoningEffort {
            let trimmedEffort = reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedEffort.isEmpty {
                payload["reasoning"] = ["effort": trimmedEffort]
            }
        }

        return payload
    }

    static func titlePrompt(userText: String) -> String {
        """
        Write a concise chat title for this user request.
        Rules:
        - 2 to 5 words.
        - Plain text only.
        - No quotes.
        - No trailing punctuation.
        User request:
        \(userText)
        """
    }

    static func generateTitleWithEphemeralRuntime(
        userText: String,
        model: String?,
        reasoningEffort: String?,
        timeoutSeconds: TimeInterval = 8
    ) async -> String? {
        let trimmedUserText = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserText.isEmpty else {
            return nil
        }

        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel: String? = {
            guard let trimmedModel, !trimmedModel.isEmpty else {
                return nil
            }
            return trimmedModel
        }()

        let trimmedEffort = reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEffort: String? = {
            guard let trimmedEffort, !trimmedEffort.isEmpty else {
                return nil
            }
            return trimmedEffort
        }()

        let runtime = CodexRuntime()
        do {
            try await runtime.start()

            let safety = RuntimeSafetyConfiguration(
                sandboxMode: .readOnly,
                approvalPolicy: .never,
                networkAccess: false,
                webSearch: .disabled,
                writableRoots: []
            )

            let threadID = try await runtime.startThread(safetyConfiguration: safety)
            let turnOptions = RuntimeTurnOptions(
                model: resolvedModel,
                effort: resolvedEffort,
                experimental: [:]
            )
            _ = try await runtime.startTurn(
                threadID: threadID,
                text: titlePrompt(userText: trimmedUserText),
                safetyConfiguration: safety,
                turnOptions: turnOptions
            )

            let stream = await runtime.events()
            let result = await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    var assistantText = ""
                    for await event in stream {
                        switch event {
                        case let .assistantMessageDelta(_, delta):
                            assistantText += delta
                        case let .turnCompleted(completion):
                            guard !isFailureStatus(completion) else {
                                return nil
                            }
                            return normalizedTitle(assistantText)
                        default:
                            continue
                        }
                    }
                    return normalizedTitle(assistantText)
                }

                group.addTask {
                    let timeoutNanoseconds = UInt64(max(timeoutSeconds, 0) * 1_000_000_000)
                    if timeoutNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    }
                    return nil
                }

                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }

            await runtime.stop()
            return result
        } catch {
            await runtime.stop()
            return nil
        }
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

    private static func isFailureStatus(_ completion: RuntimeTurnCompletion) -> Bool {
        if completion.errorMessage != nil {
            return true
        }
        let normalized = completion.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("fail")
            || normalized.contains("error")
            || normalized.contains("cancel")
    }
}
