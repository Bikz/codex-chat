import CodexChatCore
import Foundation

extension AppModel {
    func setTranscriptDetailLevel(_ level: TranscriptDetailLevel) {
        guard transcriptDetailLevel != level else { return }
        transcriptDetailLevel = level

        Task {
            do {
                try await persistTranscriptDetailLevelPreference()
            } catch {
                appendLog(.warning, "Failed to persist transcript detail level: \(error.localizedDescription)")
            }
        }
    }

    func restoreTranscriptDetailLevelPreference() async throws {
        guard let preferenceRepository else { return }

        let rawValue = try await preferenceRepository.getPreference(key: .transcriptDetailLevel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let rawValue, !rawValue.isEmpty else {
            transcriptDetailLevel = .chat
            return
        }

        transcriptDetailLevel = TranscriptDetailLevel(rawValue: rawValue) ?? .chat
    }

    func persistTranscriptDetailLevelPreference() async throws {
        guard let preferenceRepository else { return }
        try await preferenceRepository.setPreference(key: .transcriptDetailLevel, value: transcriptDetailLevel.rawValue)
    }

    func transcriptDetailLevelTitle(_ level: TranscriptDetailLevel) -> String {
        switch level {
        case .chat:
            "Chat"
        case .balanced:
            "Balanced"
        case .detailed:
            "Detailed"
        }
    }

    func transcriptDetailLevelDescription(_ level: TranscriptDetailLevel) -> String {
        switch level {
        case .chat:
            "Clean transcript: messages plus compact turn summaries."
        case .balanced:
            "Adds compact milestone context while keeping transcript tidy."
        case .detailed:
            "Shows the full action/event timeline inline."
        }
    }
}
