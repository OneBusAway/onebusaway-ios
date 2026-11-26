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

/// Manages persistent page state, bounds clamping, and wrap-around navigation
/// for the `.systemMedium` bookmarks widget.
///
/// Pure Foundation logic so `OBAKitTests` (which links `OBAKitCore` rather
/// than `OBAWidget`) can exercise pagination directly.
public final class WidgetBookmarkPaginator: Sendable {
    /// Number of bookmarks shown per page in `.systemMedium` widgets.
    public static let mediumPageSize = 2

    public static let currentPageDefaultsKey = "widgetBookmarkCurrentPage"

    /// Result of applying a pagination step.
    public struct StepResult: Equatable, Sendable {
        public let previousPage: Int
        public let currentPage: Int
        public let totalPages: Int
        public let didChangePage: Bool
    }

    private struct State {
        // UserDefaults is thread-safe. The Mutex only serializes calls on this
        // instance. Each tap builds its own paginator, so taps are kept in order
        // by `@MainActor` on `performBookmarkPageStep`, not by this lock.
        nonisolated(unsafe) let userDefaults: UserDefaults
    }

    private let state: Mutex<State>
    public let pageSize: Int

    public init(
        userDefaults: UserDefaults,
        pageSize: Int = WidgetBookmarkPaginator.mediumPageSize
    ) {
        self.state = Mutex(State(userDefaults: userDefaults))
        self.pageSize = max(1, pageSize)
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

    /// Advances to the next page, wrapping from the last page back to `0`.
    @discardableResult
    public func nextPage(bookmarkCount: Int) -> StepResult {
        step(by: 1, bookmarkCount: bookmarkCount)
    }

    /// Moves to the previous page, wrapping from `0` back to the last page.
    @discardableResult
    public func previousPage(bookmarkCount: Int) -> StepResult {
        step(by: -1, bookmarkCount: bookmarkCount)
    }

    /// Steps the current page by `delta` with wrap-around, clamping first if `bookmarkCount`
    /// shrunk.
    @discardableResult
    public func step(by delta: Int, bookmarkCount: Int) -> StepResult {
        state.withLock { state -> StepResult in
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
                    didChangePage: false
                )
            }

            let next = ((current + delta) % total + total) % total
            state.userDefaults.set(next, forKey: Self.currentPageDefaultsKey)

            return StepResult(
                previousPage: current,
                currentPage: next,
                totalPages: total,
                didChangePage: next != current
            )
        }
    }
}
