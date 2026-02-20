@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

enum VoiceCaptureAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied(reason: String)
}

enum VoiceCaptureServiceError: LocalizedError, Equatable, Sendable {
    case recognizerUnavailable
    case alreadyRecording
    case notRecording
    case captureFailed(String)
    case noSpeechDetected
    case cancelled

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            "Speech recognizer is unavailable right now. Try again in a moment."
        case .alreadyRecording:
            "Voice capture is already recording."
        case .notRecording:
            "Voice capture is not recording."
        case let .captureFailed(message):
            "Voice capture failed: \(message)"
        case .noSpeechDetected:
            "No speech detected. Try again."
        case .cancelled:
            "Voice capture was cancelled."
        }
    }
}

protocol VoiceCaptureService: AnyObject, Sendable {
    func requestAuthorization() async -> VoiceCaptureAuthorizationStatus
    func startCapture() async throws
    func stopCapture() async throws -> String
    func cancelCapture() async
}

final class AppleSpeechVoiceCaptureService: NSObject, VoiceCaptureService, @unchecked Sendable {
    private static let stopTimeoutNanoseconds: UInt64 = 3_000_000_000

    private let audioEngine: AVAudioEngine
    private let speechRecognizer: SFSpeechRecognizer?
    private let captureState = CaptureState()

    override init() {
        audioEngine = AVAudioEngine()
        speechRecognizer = SFSpeechRecognizer(locale: .current)
        super.init()
    }

    func requestAuthorization() async -> VoiceCaptureAuthorizationStatus {
        Self.debugLog("Authorization request started")

        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else {
            return .denied(reason: "Speech recognition is unavailable because the app is missing NSSpeechRecognitionUsageDescription.")
        }
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            return .denied(reason: "Voice input is unavailable because the app is missing NSMicrophoneUsageDescription.")
        }

        let speechStatus = await requestSpeechPermissionOnMainActor()
        Self.debugLog("Speech authorization status=\(speechStatus.rawValue)")
        guard speechStatus == .authorized else {
            return .denied(reason: speechAuthorizationMessage(status: speechStatus))
        }

        let micGranted = await requestMicrophonePermission()
        Self.debugLog("Microphone authorization granted=\(micGranted)")
        guard micGranted else {
            return .denied(reason: "Microphone access is required for voice input.")
        }

        return .authorized
    }

    func startCapture() async throws {
        Self.debugLog("Start capture requested")
        try await captureState.reserveForStart()

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            await captureState.rollbackStartFailure()
            throw VoiceCaptureServiceError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let task = speechRecognizer.recognitionTask(with: request) { [captureState] result, error in
            let transcription = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let mappedError = error.map(Self.mapError)

            Self.debugLog(
                "Recognition callback final=\(isFinal) hasError=\(mappedError != nil) mainThread=\(Thread.isMainThread)"
            )

            Task {
                await captureState.handleRecognitionUpdate(
                    transcription: transcription,
                    isFinal: isFinal,
                    error: mappedError
                )
            }
        }

        await captureState.attachPipeline(request: request, task: task)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            Self.debugLog("Capture started")
        } catch {
            await captureState.rollbackStartFailure()
            throw VoiceCaptureServiceError.captureFailed(error.localizedDescription)
        }
    }

    func stopCapture() async throws -> String {
        Self.debugLog("Stop capture requested")
        try await captureState.markStoppingAndEndAudio()

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        do {
            let result = try await captureState.awaitStopResult(timeoutNanoseconds: Self.stopTimeoutNanoseconds)
            Self.debugLog("Stop capture resolved with transcription")
            return result
        } catch {
            Self.debugLog("Stop capture resolved with error=\(error.localizedDescription)")
            throw error
        }
    }

    func cancelCapture() async {
        Self.debugLog("Cancel capture requested")
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        await captureState.cancelCapture()
    }

    private func requestSpeechPermissionOnMainActor() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                Task { @MainActor in
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
        @unknown default:
            return false
        }
    }

    private func speechAuthorizationMessage(status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .denied:
            "Speech recognition access was denied. Enable it in System Settings."
        case .restricted:
            "Speech recognition is restricted on this Mac."
        case .notDetermined:
            "Speech recognition permission is required for voice input."
        case .authorized:
            "Speech recognition is authorized."
        @unknown default:
            "Speech recognition is unavailable right now."
        }
    }

    private static func mapError(_ error: Error) -> VoiceCaptureServiceError {
        if let voiceError = error as? VoiceCaptureServiceError {
            return voiceError
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return .cancelled
        }
        if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 216 {
            return .cancelled
        }
        return .captureFailed(error.localizedDescription)
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
            NSLog("[VoiceCaptureService] \(message)")
        #endif
    }
}

private actor CaptureState {
    private var isCapturing = false
    private var latestTranscription = ""
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var stopContinuation: CheckedContinuation<String, Error>?
    private var stopTimeoutTask: Task<Void, Never>?

    func reserveForStart() throws {
        guard !isCapturing else {
            throw VoiceCaptureServiceError.alreadyRecording
        }

        isCapturing = true
        latestTranscription = ""
        stopContinuation = nil
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    func attachPipeline(request: SFSpeechAudioBufferRecognitionRequest, task: SFSpeechRecognitionTask) {
        recognitionRequest = request
        recognitionTask = task
    }

    func rollbackStartFailure() {
        isCapturing = false
        resetCapturePipeline(cancelRecognitionTask: true)
    }

    func markStoppingAndEndAudio() throws {
        guard isCapturing else {
            throw VoiceCaptureServiceError.notRecording
        }

        isCapturing = false
        recognitionRequest?.endAudio()
    }

    func awaitStopResult(timeoutNanoseconds: UInt64) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation

            if recognitionTask == nil {
                resolvePendingStop(with: .success(latestTranscription))
                return
            }

            scheduleStopTimeout(nanoseconds: timeoutNanoseconds)
        }
    }

    func handleRecognitionUpdate(
        transcription: String?,
        isFinal: Bool,
        error: VoiceCaptureServiceError?
    ) {
        if let transcription {
            latestTranscription = transcription
            if isFinal {
                resolvePendingStop(with: .success(transcription))
            }
        }

        if let error {
            resolvePendingStop(with: .failure(error))
        }
    }

    func cancelCapture() {
        isCapturing = false
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        resolvePendingStop(with: .failure(.cancelled))
        resetCapturePipeline(cancelRecognitionTask: true)
    }

    private func scheduleStopTimeout(nanoseconds: UInt64) {
        stopTimeoutTask?.cancel()
        stopTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self else { return }
            await self.handleStopTimeout()
        }
    }

    private func handleStopTimeout() {
        guard stopContinuation != nil else {
            return
        }

        if latestTranscription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvePendingStop(with: .failure(.noSpeechDetected))
        } else {
            resolvePendingStop(with: .success(latestTranscription))
        }
    }

    private func resolvePendingStop(with result: Result<String, VoiceCaptureServiceError>) {
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil

        guard let continuation = stopContinuation else {
            return
        }
        stopContinuation = nil

        let normalizedText = latestTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        switch result {
        case .success:
            if normalizedText.isEmpty {
                continuation.resume(throwing: VoiceCaptureServiceError.noSpeechDetected)
            } else {
                continuation.resume(returning: normalizedText)
            }
        case let .failure(error):
            continuation.resume(throwing: error)
        }

        resetCapturePipeline(cancelRecognitionTask: false)
    }

    private func resetCapturePipeline(cancelRecognitionTask: Bool) {
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
        recognitionRequest = nil

        if cancelRecognitionTask {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
    }
}
