//
//  SpeechVoiceSearchController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AVFoundation
import Foundation
import Speech

/// Live speech recognition backed by `SFSpeechRecognizer` + `AVAudioEngine`.
@MainActor
final class SpeechVoiceSearchController: VoiceSearchControlling {

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var continuation: AsyncStream<VoiceSearchEvent>.Continuation?
    /// Startup work from `start()`. Cancelled in `stop()` so a delayed permission
    /// response cannot activate the audio session after the caller ended listening —
    /// same idea as `pendingPresentation` cancellation in `SearchSheetViewModel.close()`.
    private var beginRecognitionTask: Task<Void, Never>?

    init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    var isAvailable: Bool {
        guard let speechRecognizer, speechRecognizer.isAvailable else { return false }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted:
            return false
        case .authorized, .notDetermined:
            break
        @unknown default:
            return false
        }
        // Hide the mic when the mic itself is permanently denied — speech auth alone
        // is not enough (design: hide when unavailable or permanently denied).
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            return false
        case .granted, .undetermined:
            return true
        @unknown default:
            return false
        }
    }

    func start() -> AsyncStream<VoiceSearchEvent> {
        stop()

        return AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.tearDownEngine()
                }
            }
            self.beginRecognitionTask = Task { @MainActor in
                await self.beginRecognition()
            }
        }
    }

    func stop() {
        beginRecognitionTask?.cancel()
        beginRecognitionTask = nil
        continuation?.finish()
        continuation = nil
        tearDownEngine()
    }

    // MARK: - Private

    private func beginRecognition() async {
        let speechAuthorized = await requestSpeechAuthorization()
        guard !Task.isCancelled else { return }
        guard speechAuthorized else {
            yieldPermissionDenied()
            return
        }

        let micAuthorized = await requestMicrophoneAuthorization()
        guard !Task.isCancelled else { return }
        guard micAuthorized else {
            yieldPermissionDenied()
            return
        }

        guard !Task.isCancelled else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            yield(.failed(OBALoc(
                "voice_search.unavailable",
                value: "Voice search is not available on this device.",
                comment: "Shown when SFSpeechRecognizer cannot run."
            )))
            finish()
            return
        }

        do {
            try beginAudioCapture(speechRecognizer: speechRecognizer)
        } catch {
            yield(.failed(error.localizedDescription))
            finish()
        }
    }

    private func beginAudioCapture(speechRecognizer: SFSpeechRecognizer) throws {
        try configureAudioSession()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Cloud recognition by choice: better accuracy for stop/route names than
        // on-device alone. Audio leaves the device for Apple's speech servers.
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognition(result: result, error: error)
            }
        }
    }

    private func yieldPermissionDenied() {
        yield(.failed(OBALoc(
            "voice_search.permission_denied",
            value: "Microphone or speech recognition access is required for voice search.",
            comment: "Shown when the user denies speech/mic permission for voice search."
        )))
        finish()
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let transcript = result.bestTranscription.formattedString
            if result.isFinal {
                yield(.final(transcript))
                finish()
            } else {
                yield(.partial(transcript))
            }
            return
        }

        if let error {
            // Cancellation is expected when the user stops listening.
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 216 {
                finish()
                return
            }
            yield(.failed(error.localizedDescription))
            finish()
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func tearDownEngine() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func yield(_ event: VoiceSearchEvent) {
        continuation?.yield(event)
    }

    private func finish() {
        tearDownEngine()
        continuation?.finish()
        continuation = nil
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
