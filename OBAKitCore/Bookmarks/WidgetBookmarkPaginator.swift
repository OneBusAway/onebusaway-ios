//
//  WidgetBookmarkPaginator.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Synchronization

/// Manages persistent page state, bounds clamping, wrap-around navigation,
/// and rapid-tap reload coalescing for the `.systemMedium` bookmarks widget.
///
/// Pure Foundation logic so `OBAKitTests` (which links `OBAKitCore` rather
/// than `OBAWidget`) can exercise pagination and coalescing directly.
public final class WidgetBookmarkPaginator: Sendable {
    /// Number of bookmarks shown per page in `.systemMedium` widgets.
    public static let mediumPageSize = 2

    /// Minimum interval between explicit widget timeline reloads when rapid
    /// pagination taps occur in succession.
    public static let defaultCoalesceInterval: TimeInterval = 0.25

    public static let currentPageDefaultsKey = "widgetBookmarkCurrentPage"
    public static let lastReloadTimestampDefaultsKey = "widgetBookmarkLastReloadTimestamp"

    /// Result of applying a pagination step.
    public struct StepResult: Equatable, Sendable {
        public let previousPage: Int
        public let currentPage: Int
        public let totalPages: Int
        public let didChangePage: Bool
        public let shouldReloadTimeline: Bool
    }

    private struct State {
        // UserDefaults is thread-safe, and holding it in Mutex serializes
        // read-clamp-write sequences across rapid concurrent taps.
        nonisolated(unsafe) let userDefaults: UserDefaults
    }

    private let state: Mutex<State>
    public let pageSize: Int
    public let coalesceInterval: TimeInterval
    private let onReload: (@Sendable () -> Void)?

    public init(
        userDefaults: UserDefaults,
        pageSize: Int = WidgetBookmarkPaginator.mediumPageSize,
        coalesceInterval: TimeInterval = WidgetBookmarkPaginator.defaultCoalesceInterval,
        onReload: (@Sendable () -> Void)? = nil
    ) {
        self.state = Mutex(State(userDefaults: userDefaults))
        self.pageSize = max(1, pageSize)
        self.coalesceInterval = max(0, coalesceInterval)
        self.onReload = onReload
    }

    /// Computes total pages needed to display `bookmarkCount` items at `pageSize` per page.
    public static func totalPages(bookmarkCount: Int, pageSize: Int = mediumPageSize) -> Int {
        guard bookmarkCount > 0, pageSize > 0 else { return 0 }
        return (bookmarkCount + pageSize - 1) / pageSize
    }

    /// Clamps `pageIndex` to `[0, totalPages - 1]`, returning `0` when there are no bookmarks.
    public static func clampedPage(_ pageIndex: Int, bookmarkCount: Int, pageSize: Int = mediumPageSize) -> Int {
        let pages = totalPages(bookmarkCount: bookmarkCount, pageSize: pageSize)
        guard pages > 0 else { return 0 }
        return min(max(0, pageIndex), pages - 1)
    }

    /// Returns the slice of `bookmarks` visible on `pageIndex` after clamping out-of-bounds indices.
    public static func pageSlice<T>(bookmarks: [T], pageIndex: Int, pageSize: Int = mediumPageSize) -> [T] {
        guard !bookmarks.isEmpty, pageSize > 0 else { return [] }
        let clamped = clampedPage(pageIndex, bookmarkCount: bookmarks.count, pageSize: pageSize)
        let start = clamped * pageSize
        let end = min(start + pageSize, bookmarks.count)
        return Array(bookmarks[start..<end])
    }

    /// Returns the current page clamped to `bookmarkCount`, persisting the clamped
    /// value if the bookmark count shrunk below the stored page index.
    public func currentPage(bookmarkCount: Int) -> Int {
        state.withLock { state in
            let rawStored = state.userDefaults.integer(forKey: Self.currentPageDefaultsKey)
            let clamped = Self.clampedPage(rawStored, bookmarkCount: bookmarkCount, pageSize: pageSize)
            if rawStored != clamped {
                state.userDefaults.set(clamped, forKey: Self.currentPageDefaultsKey)
            }
            return clamped
        }
    }

    /// Sets the current page clamped to `bookmarkCount` and returns the stored page index.
    @discardableResult
    public func setCurrentPage(_ pageIndex: Int, bookmarkCount: Int) -> Int {
        state.withLock { state in
            let clamped = Self.clampedPage(pageIndex, bookmarkCount: bookmarkCount, pageSize: pageSize)
            state.userDefaults.set(clamped, forKey: Self.currentPageDefaultsKey)
            return clamped
        }
    }

    /// Returns whether a timeline reload at `now` falls outside the rapid-tap coalescing window.
    public func shouldReloadTimeline(now: Date = Date()) -> Bool {
        state.withLock { state in
            Self.isOutsideCoalesceWindow(
                now: now,
                userDefaults: state.userDefaults,
                coalesceInterval: coalesceInterval
            )
        }
    }

    /// Advances to the next page, wrapping from the last page back to `0`.
    @discardableResult
    public func nextPage(bookmarkCount: Int, now: Date = Date()) -> StepResult {
        step(by: 1, bookmarkCount: bookmarkCount, now: now)
    }

    /// Moves to the previous page, wrapping from `0` back to the last page.
    @discardableResult
    public func previousPage(bookmarkCount: Int, now: Date = Date()) -> StepResult {
        step(by: -1, bookmarkCount: bookmarkCount, now: now)
    }

    /// Coalesces a burst of consecutive step deltas (e.g. `[1, 1, -1]`) into a
    /// single deterministic page update and at most one reload trigger.
    @discardableResult
    public func applyCoalescedSteps(_ deltas: [Int], bookmarkCount: Int, now: Date = Date()) -> StepResult {
        let netDelta = deltas.reduce(0, +)
        return step(by: netDelta, bookmarkCount: bookmarkCount, now: now)
    }

    /// Steps the current page by `delta` with wrap-around, clamping first if `bookmarkCount`
    /// shrunk, and coalesces duplicate rapid timeline reload triggers within `coalesceInterval`.
    @discardableResult
    public func step(by delta: Int, bookmarkCount: Int, now: Date = Date()) -> StepResult {
        let result = state.withLock { state -> StepResult in
            let total = Self.totalPages(bookmarkCount: bookmarkCount, pageSize: pageSize)
            let rawStored = state.userDefaults.integer(forKey: Self.currentPageDefaultsKey)
            let current = Self.clampedPage(rawStored, bookmarkCount: bookmarkCount, pageSize: pageSize)

            guard total > 1 else {
                if rawStored != 0 {
                    state.userDefaults.set(0, forKey: Self.currentPageDefaultsKey)
                }
                return StepResult(
                    previousPage: current,
                    currentPage: 0,
                    totalPages: total,
                    didChangePage: false,
                    shouldReloadTimeline: false
                )
            }

            let next = ((current + delta) % total + total) % total
            state.userDefaults.set(next, forKey: Self.currentPageDefaultsKey)

            let didChange = next != current
            let shouldReload: Bool
            if didChange {
                shouldReload = Self.isOutsideCoalesceWindow(
                    now: now,
                    userDefaults: state.userDefaults,
                    coalesceInterval: coalesceInterval
                )
                if shouldReload {
                    state.userDefaults.set(
                        now.timeIntervalSinceReferenceDate,
                        forKey: Self.lastReloadTimestampDefaultsKey
                    )
                }
            } else {
                shouldReload = false
            }

            return StepResult(
                previousPage: current,
                currentPage: next,
                totalPages: total,
                didChangePage: didChange,
                shouldReloadTimeline: shouldReload
            )
        }

        if result.shouldReloadTimeline {
            onReload?()
        }
        return result
    }

    private static func isOutsideCoalesceWindow(
        now: Date,
        userDefaults: UserDefaults,
        coalesceInterval: TimeInterval
    ) -> Bool {
        guard coalesceInterval > 0 else { return true }
        guard let lastTimestamp = userDefaults.object(forKey: lastReloadTimestampDefaultsKey) as? Double else {
            return true
        }
        let elapsed = now.timeIntervalSinceReferenceDate - lastTimestamp
        return elapsed >= coalesceInterval || elapsed < 0
    }
}
