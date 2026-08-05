//
//  DebouncerTests.swift
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
final class DebouncerTests {

    // These wait on a deferred main-actor callback, so — unlike the handler
    // tests elsewhere — they cannot collapse into a bare `confirmation`.
    // Execute tests use `poll`. Suppression / replacement tests deliberately
    // keep a fixed wait; see each test's own comment.

    @Test func `Debounce executes action`() async {
        var ran = false
        let debouncer = Debouncer()

        debouncer.debounce(interval: 0.1) { ran = true }

        await poll(until: { ran }, "debounced action should have run")
    }

    @Test func `Throttle executes action`() async {
        var ran = false
        let throttler = Throttler()

        throttler.throttle(deadline: .now() + 0.1) { ran = true }

        await poll(until: { ran }, "throttled action should have run")
    }

    @Test func `Debounce suppresses second call within interval`() async throws {
        var count = 0
        let debouncer = Debouncer()

        // Same instance (and optional shared context): bookkeeping is owned by
        // the Debouncer, not a process-global map, so a fresh instance per test
        // is enough isolation. Context still mirrors the multi-consumer API.
        let context = "test_debounce_suppression"
        debouncer.debounce(interval: 0.5, context: context) { count += 1 }
        debouncer.debounce(interval: 0.5, context: context) { count += 1 }

        // Deliberately a fixed wait rather than a poll: the assertion is that a
        // second call never lands, and polling for "count == 1" would pass the
        // instant the first one did — before the suppressed one could show up.
        try await Task.sleep(for: .milliseconds(200))

        #expect(count == 1)
    }

    /// Counts runs rather than overwriting a value: if cancellation were broken
    /// both workers would fire and `runs` would be 2. Overwriting `value = 1`
    /// then `value = 2` still ends at 2 whether or not the first was cancelled.
    @Test func `Throttle replaces pending action`() async throws {
        var runs = 0
        let throttler = Throttler()

        throttler.throttle(deadline: .now() + .milliseconds(150)) { runs += 1 }
        throttler.throttle(deadline: .now() + .milliseconds(150)) { runs += 1 }

        try await Task.sleep(for: .milliseconds(300))

        #expect(runs == 1)
    }
}
