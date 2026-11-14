//
//  WidgetTimelineReloader.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)

import Foundation
import WidgetKit

/// Throttles and safely triggers widget timeline reloads.
///
/// WidgetKit allocates each widget an execution budget of 40–70 timeline reloads per day.
/// When a user rapidly taps the widget's interactive refresh button, repeated calls to
/// `WidgetCenter.shared.reloadAllTimelines()` can quickly deplete this quota or degrade
/// system responsiveness.
///
/// `WidgetTimelineReloader` enforces a minimum cooldown interval between reloads (defaulting
/// to 5 seconds), debouncing rapid successive taps. In addition, it protects callers from
/// unexpected runtime exceptions or errors during reload execution, guaranteeing that
/// interactive `AppIntent` operations complete truthfully and never trap.
public actor WidgetTimelineReloader {

    /// Default minimum interval required between consecutive timeline reloads (5 seconds).
    public static let defaultCooldownInterval: TimeInterval = 5.0

    /// Outcome of a refresh / reload attempt.
    public enum Result: Equatable, Sendable {
        /// Timeline reload was successfully executed.
        case success

        /// Reload was skipped because another reload occurred within the cooldown interval.
        case throttled

        /// Reload failed with an error, but was safely handled without trapping.
        case failure

        /// Widget data or service is unavailable, handled safely without trapping.
        case unavailable

        /// Alias for `.success` to support alternate naming.
        public static let reloaded: Result = .success
    }

    /// Global shared instance used by widget intents.
    public static let shared = WidgetTimelineReloader()

    public let cooldownInterval: TimeInterval
    private let clock: @Sendable () -> Date
    private let reloadAction: @Sendable () async throws -> Void

    private var lastReloadDate: Date?

    /// Creates a reloader with configurable cooldown interval, clock, and reload action.
    ///
    /// - Parameters:
    ///   - cooldownInterval: Minimum time interval (in seconds) between allowed reloads.
    ///   - clock: Closure returning current date; allows injecting simulated time in tests.
    ///   - reloadAction: Async throwing closure performing reload. Defaults to `WidgetCenter.shared.reloadAllTimelines()`.
    public init(
        cooldownInterval: TimeInterval = defaultCooldownInterval,
        clock: @escaping @Sendable () -> Date = { Date() },
        reloadAction: (@Sendable () async throws -> Void)? = nil
    ) {
        self.cooldownInterval = cooldownInterval
        self.clock = clock
        self.reloadAction = reloadAction ?? {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Triggers a widget timeline reload if the cooldown interval has elapsed since the last reload.
    ///
    /// Never throws or traps.
    /// - Returns: A `Result` describing whether the reload took place, was throttled, or failed.
    @discardableResult
    public func reload() async -> Result {
        let now = clock()

        if let lastReload = lastReloadDate, now.timeIntervalSince(lastReload) < cooldownInterval {
            return .throttled
        }

        lastReloadDate = now

        do {
            try await reloadAction()
            return .success
        } catch let error as WidgetReloadError {
            switch error {
            case .unavailable:
                return .unavailable
            case .failed:
                return .failure
            }
        } catch {
            return .failure
        }
    }

    /// Resets the internal cooldown state.
    public func reset() {
        lastReloadDate = nil
    }
}

/// Typealias for alternative naming flexibility.
public typealias WidgetRefreshThrottler = WidgetTimelineReloader

/// Errors that can be thrown by a custom reload action to test failure handling.
public enum WidgetReloadError: Error, Equatable, Sendable {
    case unavailable
    case failed
}

#endif // os(iOS)
