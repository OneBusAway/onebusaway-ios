//
//  VoiceSearchControlling.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Events from an in-progress voice recognition session.
enum VoiceSearchEvent: Equatable {
    case partial(String)
    case final(String)
    case failed(String)
}

/// Abstracts speech recognition so `SearchSheetViewModel` can be tested without
/// microphone / Speech entitlements.
@MainActor
protocol VoiceSearchControlling: AnyObject {
    /// `false` when speech or the microphone cannot run (unavailable or permanently denied).
    var isAvailable: Bool { get }

    /// Starts listening. Yields partial transcripts, then a single `.final` (or `.failed`).
    func start() -> AsyncStream<VoiceSearchEvent>

    /// Stops listening without producing a final result.
    func stop()
}
