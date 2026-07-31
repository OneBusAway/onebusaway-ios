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
@MainActor
public final class Debouncer {
    private var lastCallTimes: [AnyHashable: DispatchTime] = [:]
    private var cleanupWorkItems: [AnyHashable: DispatchWorkItem] = [:]
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

        cleanupWorkItems[key]?.cancel()
        let cleanup = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.lastCallTimes.removeValue(forKey: key)
                self?.cleanupWorkItems.removeValue(forKey: key)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: cleanup)
        cleanupWorkItems[key] = cleanup
    }
}

/// Trailing delay for main-actor work: schedules `action` for `deadline`, and
/// a newer call with the same `context` cancels the pending one.
///
/// Replaces the old `DispatchQueue.throttle` helper (#1196).
@MainActor
public final class Throttler {
    private var workItems: [AnyHashable: DispatchWorkItem] = [:]
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
        workItems[key]?.cancel()

        let worker = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.workItems.removeValue(forKey: key)
                action()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: deadline, execute: worker)
        workItems[key] = worker
    }
}
