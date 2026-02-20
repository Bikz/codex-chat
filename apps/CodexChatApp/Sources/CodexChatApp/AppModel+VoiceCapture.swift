import Foundation

extension AppModel {
    var composerStarterPrompts: [String] {
        [
            "What's on my calendar today?",
            "Clean up my desktop files.",
            "Send message to Alex: Running 10 minutes late.",
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
        let invalidatedSession = invalidateVoiceCaptureSession()
        stopVoiceCaptureElapsedTicker()
        voiceAutoStopTask?.cancel()
        voiceAutoStopTask = nil
        voiceCaptureState = .idle
        debugVoiceCapture("Cancelled voice capture; invalidated session=\(invalidatedSession)")

        Task { [voiceCaptureService] in
            await voiceCaptureService.cancelCapture()
        }
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
        let sessionID = beginVoiceCaptureSession()
        guard canSubmitComposer else {
            stopVoiceCaptureElapsedTicker()
            voiceCaptureState = .failed(message: "Voice input is unavailable until the runtime is ready.")
            return
        }

        stopVoiceCaptureElapsedTicker()
        voiceCaptureState = .requestingPermission
        debugVoiceCapture("Begin voice capture session=\(sessionID)")
        Task { @MainActor [weak self] in
            guard let self else { return }

            let authorization = await voiceCaptureService.requestAuthorization()
            guard isCurrentVoiceCaptureSession(sessionID) else {
                debugVoiceCapture("Ignoring stale authorization response for session=\(sessionID)")
                return
            }

            switch authorization {
            case .authorized:
                do {
                    try await voiceCaptureService.startCapture()
                    guard isCurrentVoiceCaptureSession(sessionID) else {
                        debugVoiceCapture("Ignoring stale start capture completion for session=\(sessionID)")
                        await voiceCaptureService.cancelCapture()
                        return
                    }

                    voiceCaptureState = .recording(startedAt: Date())
                    startVoiceCaptureElapsedTicker()
                    scheduleVoiceCaptureAutoStop()
                    debugVoiceCapture("Voice capture recording started for session=\(sessionID)")
                } catch {
                    guard isCurrentVoiceCaptureSession(sessionID) else {
                        debugVoiceCapture("Ignoring stale start capture error for session=\(sessionID)")
                        return
                    }
                    stopVoiceCaptureElapsedTicker()
                    voiceCaptureState = .failed(message: error.localizedDescription)
                }
            case let .denied(reason):
                guard isCurrentVoiceCaptureSession(sessionID) else {
                    debugVoiceCapture("Ignoring stale denial for session=\(sessionID)")
                    return
                }
                stopVoiceCaptureElapsedTicker()
                voiceCaptureState = .failed(message: reason)
            }
        }
    }

    private func stopVoiceCapture(reason: VoiceCaptureStopReason) {
        guard case .recording = voiceCaptureState else {
            return
        }
        let sessionID = voiceCaptureSessionID

        voiceAutoStopTask?.cancel()
        voiceAutoStopTask = nil
        stopVoiceCaptureElapsedTicker()
        voiceCaptureState = .transcribing
        debugVoiceCapture("Stopping voice capture for session=\(sessionID) reason=\(reason)")

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let transcription = try await voiceCaptureService.stopCapture()
                guard isCurrentVoiceCaptureSession(sessionID) else {
                    debugVoiceCapture("Ignoring stale stop capture completion for session=\(sessionID)")
                    return
                }
                handleVoiceTranscriptionResult(transcription)
            } catch VoiceCaptureServiceError.cancelled {
                guard isCurrentVoiceCaptureSession(sessionID) else {
                    debugVoiceCapture("Ignoring stale cancellation for session=\(sessionID)")
                    return
                }
                voiceCaptureState = .idle
            } catch VoiceCaptureServiceError.noSpeechDetected where reason == .timeout {
                guard isCurrentVoiceCaptureSession(sessionID) else {
                    debugVoiceCapture("Ignoring stale timeout result for session=\(sessionID)")
                    return
                }
                voiceCaptureState = .failed(message: "Stopped after 90 seconds with no speech detected.")
            } catch {
                guard isCurrentVoiceCaptureSession(sessionID) else {
                    debugVoiceCapture("Ignoring stale stop capture error for session=\(sessionID)")
                    return
                }
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

    @discardableResult
    private func beginVoiceCaptureSession() -> UInt64 {
        incrementVoiceCaptureSessionID()
        return voiceCaptureSessionID
    }

    @discardableResult
    private func invalidateVoiceCaptureSession() -> UInt64 {
        incrementVoiceCaptureSessionID()
        return voiceCaptureSessionID
    }

    private func incrementVoiceCaptureSessionID() {
        voiceCaptureSessionID &+= 1
        if voiceCaptureSessionID == 0 {
            voiceCaptureSessionID = 1
        }
    }

    private func isCurrentVoiceCaptureSession(_ sessionID: UInt64) -> Bool {
        voiceCaptureSessionID == sessionID
    }

    private func debugVoiceCapture(_ message: String) {
        #if DEBUG
            NSLog("[VoiceCapture] \(message)")
        #endif
    }
}
