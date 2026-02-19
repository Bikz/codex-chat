import Foundation

extension AppModel {
    var composerStarterPrompts: [String] {
        [
            "What's on my calendar today?",
            "Set up OpenClaw on a VM using Google CLI.",
            "Review this repo for risky code paths.",
        ]
    }

    var shouldShowComposerStarterPrompts: Bool {
        composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && composerAttachments.isEmpty
            && canSubmitComposer
            && !isVoiceCaptureInProgress
    }

    var isVoiceCaptureInProgress: Bool {
        switch voiceCaptureState {
        case .requestingPermission, .recording, .transcribing:
            true
        case .idle, .failed:
            false
        }
    }

    var isVoiceCaptureRecording: Bool {
        if case .recording = voiceCaptureState {
            return true
        }
        return false
    }

    var canToggleVoiceCapture: Bool {
        switch voiceCaptureState {
        case .requestingPermission, .transcribing:
            false
        case .recording:
            true
        case .idle, .failed:
            canSubmitComposer
        }
    }

    var voiceCaptureStatusMessage: String? {
        switch voiceCaptureState {
        case .idle:
            nil
        case .requestingPermission:
            "Requesting microphone and speech recognition permissions..."
        case .recording:
            "Listening..."
        case .transcribing:
            "Transcribing..."
        case let .failed(message):
            message
        }
    }

    func voiceRecordingElapsed(now: Date = Date()) -> String? {
        guard case let .recording(startedAt) = voiceCaptureState else {
            return nil
        }
        let elapsedSeconds = max(0, Int(now.timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    func insertStarterPrompt(_ prompt: String) {
        composerText = prompt
    }

    func toggleVoiceCapture() {
        switch voiceCaptureState {
        case .idle, .failed:
            beginVoiceCapture()
        case .recording:
            stopVoiceCapture(reason: .manual)
        case .requestingPermission, .transcribing:
            break
        }
    }

    func cancelVoiceCapture() {
        voiceAutoStopTask?.cancel()
        voiceAutoStopTask = nil
        voiceCaptureService.cancelCapture()
        voiceCaptureState = .idle
    }

    func handleVoiceTranscriptionResult(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            voiceCaptureState = .failed(message: VoiceCaptureServiceError.noSpeechDetected.localizedDescription)
            return
        }

        let existing = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        composerText = existing.isEmpty ? trimmed : "\(existing)\n\n\(trimmed)"
        voiceCaptureState = .idle
    }

    private enum VoiceCaptureStopReason {
        case manual
        case timeout
    }

    private func beginVoiceCapture() {
        guard canSubmitComposer else {
            voiceCaptureState = .failed(message: "Voice input is unavailable until the runtime is ready.")
            return
        }

        voiceCaptureState = .requestingPermission
        Task { @MainActor [weak self] in
            guard let self else { return }

            let authorization = await voiceCaptureService.requestAuthorization()
            switch authorization {
            case .authorized:
                do {
                    try voiceCaptureService.startCapture()
                    voiceCaptureState = .recording(startedAt: Date())
                    scheduleVoiceCaptureAutoStop()
                } catch {
                    voiceCaptureState = .failed(message: error.localizedDescription)
                }
            case let .denied(reason):
                voiceCaptureState = .failed(message: reason)
            }
        }
    }

    private func stopVoiceCapture(reason: VoiceCaptureStopReason) {
        guard case .recording = voiceCaptureState else {
            return
        }

        voiceAutoStopTask?.cancel()
        voiceAutoStopTask = nil
        voiceCaptureState = .transcribing

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let transcription = try await voiceCaptureService.stopCapture()
                handleVoiceTranscriptionResult(transcription)
            } catch VoiceCaptureServiceError.cancelled {
                voiceCaptureState = .idle
            } catch VoiceCaptureServiceError.noSpeechDetected where reason == .timeout {
                voiceCaptureState = .failed(message: "Stopped after 90 seconds with no speech detected.")
            } catch {
                voiceCaptureState = .failed(message: error.localizedDescription)
            }
        }
    }

    private func scheduleVoiceCaptureAutoStop() {
        voiceAutoStopTask?.cancel()
        voiceAutoStopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: voiceAutoStopDurationNanoseconds)
            guard case .recording = voiceCaptureState else { return }
            stopVoiceCapture(reason: .timeout)
        }
    }
}
