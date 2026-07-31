//
//  Debouncer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Dispatch
import Foundation

/// Leading-edge cooldown for main-actor work: the first call runs (on the next
/// main turn), and further calls within `interval` are ignored until the
/// window clears.
///
/// Replaces the old `DispatchQueue.debounce` helper (#1196). Being `@MainActor`
/// makes misuse off the main actor a compile error, instead of a debug assert
/// / `MainActor.assumeIsolated` trap at runtime.
///
/// Cleanup is a cancellable `Task` that removes bookkeeping synchronously on
/// the main actor after `interval` — not a `DispatchWorkItem` that hops through
/// a second `Task`. The hop pattern could delete a fresher window that landed
/// between the work item firing and the deferred task running.
@MainActor
public final class Debouncer {
    private var lastCallTimes: [AnyHashable: DispatchTime] = [:]
    private var cleanupTasks: [AnyHashable: Task<Void, Never>] = [:]
    private let defaultContext: AnyHashable = UUID()

    public init() {}

    /// - Parameters:
    ///   - interval: Seconds during which subsequent calls with the same
    ///     `context` are ignored after a successful call.
    ///   - context: Optional key when one Debouncer gates several independent
    ///     call sites. Defaults to a per-instance sentinel.
    ///   - action: Work to run on the main actor.
    public func debounce(
        interval: Double,
        context: AnyHashable? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        let key = context ?? defaultContext
        if let last = lastCallTimes[key], last + interval > .now() {
            return
        }

        lastCallTimes[key] = .now()

        // Hop a turn so `action` isn't re-entrant into the caller's stack —
        // matches the previous `DispatchQueue.async` behavior.
        Task { @MainActor in
            action()
        }

        cleanupTasks[key]?.cancel()
        cleanupTasks[key] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            lastCallTimes.removeValue(forKey: key)
            cleanupTasks.removeValue(forKey: key)
        }
    }
}

/// Trailing delay for main-actor work: schedules `action` for `deadline`, and
/// a newer call with the same `context` cancels the pending one.
///
/// Replaces the old `DispatchQueue.throttle` helper (#1196).
///
/// The pending worker is a cancellable `Task` that clears its own bookkeeping
/// and runs `action` synchronously on the main actor — same ordering fix as
/// ``Debouncer`` (no `DispatchWorkItem` → deferred `Task` hop).
@MainActor
public final class Throttler {
    private var pendingTasks: [AnyHashable: Task<Void, Never>] = [:]
    private let defaultContext: AnyHashable = UUID()

    public init() {}

    /// - Parameters:
    ///   - deadline: When the action should run (`DispatchTime.now() + …`).
    ///   - context: Optional key when one Throttler gates several independent
    ///     call sites. Defaults to a per-instance sentinel.
    ///   - action: Work to run on the main actor.
    public func throttle(
        deadline: DispatchTime,
        context: AnyHashable? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        let key = context ?? defaultContext
        pendingTasks[key]?.cancel()

        let delayNanoseconds = Self.nanosecondsUntil(deadline)
        pendingTasks[key] = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            pendingTasks.removeValue(forKey: key)
            action()
        }
    }

    /// Converts a `DispatchTime` deadline into a sleep duration. Past deadlines
    /// yield `0` so the action still runs on the next main turn after cancel
    /// checks — matching `DispatchQueue.main.asyncAfter` with a past deadline.
    private static func nanosecondsUntil(_ deadline: DispatchTime) -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        let target = deadline.uptimeNanoseconds
        return target > now ? target - now : 0
    }
}
