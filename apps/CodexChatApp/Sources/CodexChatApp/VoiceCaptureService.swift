import AVFoundation
import Foundation
import Speech

enum VoiceCaptureAuthorizationStatus: Equatable {
    case authorized
    case denied(reason: String)
}

enum VoiceCaptureServiceError: LocalizedError, Equatable {
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

@MainActor
protocol VoiceCaptureService: AnyObject {
    func requestAuthorization() async -> VoiceCaptureAuthorizationStatus
    func startCapture() throws
    func stopCapture() async throws -> String
    func cancelCapture()
}

@MainActor
final class AppleSpeechVoiceCaptureService: NSObject, VoiceCaptureService {
    private let audioEngine: AVAudioEngine
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var stopContinuation: CheckedContinuation<String, Error>?
    private var stopTimeoutTask: Task<Void, Never>?
    private var latestTranscription = ""
    private var isCapturing = false

    override init() {
        audioEngine = AVAudioEngine()
        speechRecognizer = SFSpeechRecognizer(locale: .current)
        super.init()
    }

    func requestAuthorization() async -> VoiceCaptureAuthorizationStatus {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else {
            return .denied(reason: "Speech recognition is unavailable because the app is missing NSSpeechRecognitionUsageDescription.")
        }
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            return .denied(reason: "Voice input is unavailable because the app is missing NSMicrophoneUsageDescription.")
        }

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            return .denied(reason: speechAuthorizationMessage(status: speechStatus))
        }

        let micGranted = await requestMicrophonePermission()
        guard micGranted else {
            return .denied(reason: "Microphone access is required for voice input.")
        }

        return .authorized
    }

    func startCapture() throws {
        guard !isCapturing else {
            throw VoiceCaptureServiceError.alreadyRecording
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw VoiceCaptureServiceError.recognizerUnavailable
        }

        resetCapturePipeline(cancelRecognitionTask: true)
        latestTranscription = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    latestTranscription = result.bestTranscription.formattedString
                    if result.isFinal {
                        resolvePendingStop(with: .success(latestTranscription))
                    }
                }

                if let error {
                    resolvePendingStop(with: .failure(error))
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isCapturing = true
        } catch {
            resetCapturePipeline(cancelRecognitionTask: true)
            throw VoiceCaptureServiceError.captureFailed(error.localizedDescription)
        }
    }

    func stopCapture() async throws -> String {
        guard isCapturing else {
            throw VoiceCaptureServiceError.notRecording
        }

        isCapturing = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation

            if recognitionTask == nil {
                resolvePendingStop(with: .success(latestTranscription))
                return
            }

            scheduleStopTimeout()
        }
    }

    func cancelCapture() {
        isCapturing = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        resolvePendingStop(with: .failure(VoiceCaptureServiceError.cancelled))
        resetCapturePipeline(cancelRecognitionTask: true)
    }

    private func scheduleStopTimeout() {
        stopTimeoutTask?.cancel()
        stopTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            guard stopContinuation != nil else { return }

            if latestTranscription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolvePendingStop(with: .failure(VoiceCaptureServiceError.noSpeechDetected))
            } else {
                resolvePendingStop(with: .success(latestTranscription))
            }
        }
    }

    private func resolvePendingStop(with result: Result<String, Error>) {
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
            continuation.resume(throwing: mapError(error))
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

    private func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
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

    private func mapError(_ error: Error) -> Error {
        if let error = error as? VoiceCaptureServiceError {
            return error
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return VoiceCaptureServiceError.cancelled
        }
        if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 216 {
            return VoiceCaptureServiceError.cancelled
        }
        return VoiceCaptureServiceError.captureFailed(error.localizedDescription)
    }
}
