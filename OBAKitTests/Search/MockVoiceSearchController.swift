//
//  MockVoiceSearchController.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
@testable import OBAKit

/// Scripted voice search for `SearchSheetViewModel` tests.
///
/// Events emitted before the view model's `for await` subscribes are buffered so
/// tests don't have to race the unstructured `Task` that `startVoiceSearch` opens.
@MainActor
final class MockVoiceSearchController: VoiceSearchControlling {
    var isAvailable = true
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var continuation: AsyncStream<VoiceSearchEvent>.Continuation?
    private var pending: [VoiceSearchEvent] = []

    func start() -> AsyncStream<VoiceSearchEvent> {
        startCount += 1
        // Don't call `stop()` here — that would finish a brand-new stream's
        // continuation if `start` is nested oddly, and it inflated `stopCount`
        // on every listen. Tear down only via explicit `stop()`.
        return AsyncStream { continuation in
            self.continuation = continuation
            let buffered = self.pending
            self.pending.removeAll()
            for event in buffered {
                self.deliver(event, to: continuation)
            }
        }
    }

    func stop() {
        stopCount += 1
        continuation?.finish()
        continuation = nil
        pending.removeAll()
    }

    func emit(_ event: VoiceSearchEvent) {
        if let continuation {
            deliver(event, to: continuation)
        } else {
            pending.append(event)
        }
    }

    private func deliver(_ event: VoiceSearchEvent, to continuation: AsyncStream<VoiceSearchEvent>.Continuation) {
        continuation.yield(event)
        switch event {
        case .final, .failed:
            continuation.finish()
            self.continuation = nil
        case .partial:
            break
        }
    }
}
