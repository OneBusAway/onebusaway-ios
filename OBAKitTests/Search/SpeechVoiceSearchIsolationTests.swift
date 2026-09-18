//
//  SpeechVoiceSearchIsolationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AVFoundation
import Foundation
import Speech
import Testing
@testable import OBAKit

/// The audio tap and the speech-authorization handler run off the main actor.
/// A `@MainActor` closure traps there (`swift_task_reportUnexpectedExecutor`).
/// These call the same helpers production installs, from a background executor.
@Suite(.serialized)
struct SpeechVoiceSearchIsolationTests {

    @Test nonisolated func `Audio tap block appends off the main actor`() async {
        await Task.detached {
            let request = SFSpeechAudioBufferRecognitionRequest()
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
            buffer.frameLength = 1
            let block = SpeechVoiceSearchController.captureTapBlock(appendingTo: request)
            block(buffer, AVAudioTime())
        }.value
    }

    @Test nonisolated func `Speech authorization handler resumes off the main actor`() async {
        let authorized = await Task.detached {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let handler = SpeechVoiceSearchController.speechAuthorizationHandler { granted in
                    continuation.resume(returning: granted)
                }
                handler(.authorized)
            }
        }.value

        #expect(authorized)
    }
}
