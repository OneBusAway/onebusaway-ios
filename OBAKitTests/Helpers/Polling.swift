//
//  Polling.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing

/// Waits for `condition` to become true, or records an issue when it doesn't.
///
/// This is the replacement for Nimble's `toEventually`, which is the one
/// capability Swift Testing has no equivalent for: `confirmation()` counts
/// events within a scope and `.timeLimit()` bounds a whole test, but neither
/// polls a condition. See docs/swift6-migration-plan.md, "Is Nimble still
/// worth it?".
///
/// **Prefer awaiting a real signal over polling.** Most "eventually" tests
/// exist because production code fires an unowned `Task` the test can't await;
/// giving that task an owner turns a fuzzy poll into an exact assertion (see
/// `StopViewModel.surveyRefreshTask`). Reach for this only when there is
/// genuinely no completion to await — e.g. observing a side effect of a
/// non-terminating auto-refresh loop.
///
/// Returns as soon as the condition holds, so a passing test pays only the
/// poll interval, not the timeout.
///
/// - Parameters:
///   - condition: Evaluated on the main actor until it returns `true`.
///   - timeout: How long to keep trying before recording a failure.
///   - interval: How long to wait between evaluations.
///   - message: Describes what was expected, used in the failure message.
@MainActor
func poll(
    until condition: @MainActor () -> Bool,
    timeout: Duration = .seconds(2),
    interval: Duration = .milliseconds(10),
    _ message: @autoclosure () -> String = "condition never became true",
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() {
            return
        }
        try? await Task.sleep(for: interval)
    }

    // One last evaluation: a condition that flipped during the final sleep
    // should pass rather than fail on a scheduling technicality.
    if condition() {
        return
    }

    Issue.record(
        "poll timed out after \(timeout): \(message())",
        sourceLocation: sourceLocation
    )
}

/// Lets queued main-actor work and in-flight animations run for `seconds`.
///
/// This replaced `RunLoop.current.run(until:)`, which used to work and no longer
/// does. Under XCTest a test method ran directly on the main thread's run loop,
/// so blocking there still drained the main queue. A Swift Testing `@MainActor`
/// test body is itself a main-queue item, and blocking inside it cannot
/// re-entrantly drain further main-queue blocks — UIView animation completion
/// handlers simply never fire. Suspending releases the main actor, which is what
/// actually lets that work run.
///
/// Prefer ``poll(until:timeout:interval:_:sourceLocation:)`` when there is a
/// condition to wait on: it returns as soon as the condition holds, where this
/// always burns the full duration. Use this only to let an animation of known
/// length play out.
func spin(_ seconds: TimeInterval) async {
    try? await Task.sleep(for: .seconds(seconds))
}
