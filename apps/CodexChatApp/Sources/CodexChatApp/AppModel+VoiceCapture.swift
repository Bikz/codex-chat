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
        let hasNoConversationEntries: Bool = {
            guard case let .loaded(entries) = conversationState else {
                return false
            }
            return entries.isEmpty
        }()

        return composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && composerAttachments.isEmpty
            && canSubmitComposer
            && !isVoiceCaptureInProgress
            && hasNoConversationEntries
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
        stopVoiceCaptureElapsedTicker()
        voiceAutoStopTask?.cancel()
        voiceAutoStopTask = nil
        voiceCaptureService.cancelCapture()
        voiceCaptureState = .idle
    }

    func handleVoiceTranscriptionResult(_ text: String) {
        stopVoiceCaptureElapsedTicker()
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
            stopVoiceCaptureElapsedTicker()
            voiceCaptureState = .failed(message: "Voice input is unavailable until the runtime is ready.")
            return
        }

        stopVoiceCaptureElapsedTicker()
        voiceCaptureState = .requestingPermission
        Task { @MainActor [weak self] in
            guard let self else { return }

            let authorization = await voiceCaptureService.requestAuthorization()
            switch authorization {
            case .authorized:
                do {
                    try voiceCaptureService.startCapture()
                    voiceCaptureState = .recording(startedAt: Date())
                    startVoiceCaptureElapsedTicker()
                    scheduleVoiceCaptureAutoStop()
                } catch {
                    stopVoiceCaptureElapsedTicker()
                    voiceCaptureState = .failed(message: error.localizedDescription)
                }
            case let .denied(reason):
                stopVoiceCaptureElapsedTicker()
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
        stopVoiceCaptureElapsedTicker()
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

    private func startVoiceCaptureElapsedTicker() {
        voiceCaptureRecordingStart = voiceElapsedClock.now
        updateVoiceCaptureElapsedText()

        voiceElapsedTickerTask?.cancel()
        voiceElapsedTickerTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await voiceElapsedClock.sleep(for: .seconds(1))
                } catch {
                    return
                }

                guard case .recording = voiceCaptureState else {
                    return
                }
                updateVoiceCaptureElapsedText()
            }
        }
    }

    private func stopVoiceCaptureElapsedTicker() {
        voiceElapsedTickerTask?.cancel()
        voiceElapsedTickerTask = nil
        voiceCaptureRecordingStart = nil
        voiceCaptureElapsedText = nil
    }

    private func updateVoiceCaptureElapsedText() {
        guard let startedAt = voiceCaptureRecordingStart else {
            voiceCaptureElapsedText = nil
            return
        }
        let duration = startedAt.duration(to: voiceElapsedClock.now)
        let elapsedSeconds = max(0, Int(duration.components.seconds))
        voiceCaptureElapsedText = String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
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
