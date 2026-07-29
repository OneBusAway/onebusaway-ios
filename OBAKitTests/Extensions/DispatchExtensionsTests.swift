//
//  DispatchExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class DispatchExtensionsTests {
    
    // These three genuinely wait on a dispatch callback, so — unlike the
    // handler tests elsewhere — they cannot collapse into a bare
    // `confirmation`. The first two use `poll`, the repo's replacement for
    // "wait until this becomes true", which returns as soon as the condition
    // holds rather than burning the full timeout the way `waitForExpectations`
    // did. The third deliberately keeps a fixed wait; see its own comment.

    @Test func `Debounce executes action`() async {
        var ran = false

        DispatchQueue.main.debounce(interval: 0.1) { ran = true }

        await poll(until: { ran }, "debounced action should have run")
    }

    @Test func `Throttle executes action`() async {
        var ran = false

        DispatchQueue.main.throttle(deadline: .now() + 0.1) { ran = true }

        await poll(until: { ran }, "throttled action should have run")
    }

    @Test func `Debounce suppresses second call within interval`() async throws {
        var count = 0

        // Unique context: the debounce bookkeeping is global and would otherwise
        // leak across tests.
        let context = "test_debounce_suppression"
        DispatchQueue.main.debounce(interval: 0.5, context: context) { count += 1 }
        DispatchQueue.main.debounce(interval: 0.5, context: context) { count += 1 }

        // Deliberately a fixed wait rather than a poll: the assertion is that a
        // second call never lands, and polling for "count == 1" would pass the
        // instant the first one did — before the suppressed one could show up.
        try await Task.sleep(for: .milliseconds(200))

        #expect(count == 1)
    }
}
