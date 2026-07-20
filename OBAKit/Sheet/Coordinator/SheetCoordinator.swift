//
//  SheetCoordinator.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

// MARK: - SheetCoordinator

/// Owns the route stacks for both the base (content-swap) sheet and the
/// stacked layer (a stack of physical sheets, each peeking behind the next).
@MainActor
final class SheetCoordinator<Route: SheetRouteable>: ObservableObject {

    // MARK: - Content-swap layer (base sheet)

    /// The route always present at the bottom of the content-swap stack.
    /// Stored separately so `currentRoute` never has to force-unwrap.
    let root: Route

    /// Routes pushed on top of `root`. Empty when the base sheet is showing root.
    @Published private(set) var additionalRoutes: [Route] = []

    @Published var currentDetent: PresentationDetent

    var currentRoute: Route { additionalRoutes.last ?? root }
    var routeStack: [Route] { [root] + additionalRoutes }
    var currentDetents: Set<PresentationDetent> { currentRoute.detentConfiguration.detents }
    var canPop: Bool { !additionalRoutes.isEmpty || !stackedEntries.isEmpty }

    // MARK: - Stacked layer

    /// A route paired with its currently-selected detent. One entry per
    /// physical sheet in the stacked pile, index 0 closest to the base sheet.
    struct StackedEntry: Equatable {
        let route: Route
        var detent: PresentationDetent
    }

    /// Stacked-sheet pile. Empty when no stacked sheets are presented.
    @Published private(set) var stackedEntries: [StackedEntry] = []

    var stackedRoutes: [Route] { stackedEntries.map(\.route) }
    var stackedDetents: [PresentationDetent] { stackedEntries.map(\.detent) }

    // MARK: - Init

    init(root: Route) {
        self.root = root
        currentDetent = root.detentConfiguration.initialDetent
    }

    // Workaround for a Swift 6.3 (Xcode 26.4) SIL optimizer crash: the
    // EarlyPerfInliner segfaults inlining into this generic MainActor class's
    // synthesized deinit under `-O`, so `xcodebuild archive` (Release) fails
    // while Debug builds and Xcode 27 (Swift 6.4, bug fixed) are fine. Pinning
    // this empty deinit to `@_optimize(none)` keeps the inliner off it. Remove
    // once the minimum toolchain is past the fix.
    @_optimize(none)
    deinit {}

    // MARK: - Unified navigation

    /// Pushes a route on whichever layer it prefers.
    /// Stacked routes append a new physical sheet over the previous one;
    /// content-swap routes append to the base content stack.
    ///
    /// Invariant: a stacked route must allow interactive dismissal. The OS
    /// owns drag-down on the stacked layer, and `truncateStacked` is wired
    /// to that gesture — locking dismissal would let `stackedEntries` point
    /// at a sheet that's no longer on screen.
    func push(_ route: Route) {
        if route.prefersStacking {
            precondition(
                !route.detentConfiguration.isDismissDisabled,
                "Stacked routes must have isDismissDisabled == false; \(route) does not."
            )
            stackedEntries.append(StackedEntry(route: route, detent: route.detentConfiguration.initialDetent))
        } else {
            additionalRoutes.append(route)
            currentDetent = route.detentConfiguration.initialDetent
        }
    }

    /// Pops the top of whichever layer is on top: frontmost stacked sheet if
    /// any, otherwise the content-stack top. No-op at root.
    func pop() {
        if !stackedEntries.isEmpty {
            stackedEntries.removeLast()
            return
        }
        guard !additionalRoutes.isEmpty else { return }
        additionalRoutes.removeLast()
        currentDetent = currentRoute.detentConfiguration.initialDetent
    }

    /// Removes every stacked sheet at or above the given depth. Called by the
    /// container when the OS dismisses a sheet (drag-down) so storage stays in
    /// sync with what's actually on screen.
    func truncateStacked(toDepth depth: Int) {
        guard depth >= 0, depth < stackedEntries.count else { return }
        stackedEntries.removeSubrange(depth...)
    }

    /// Updates the stored detent for the stacked sheet at `depth`.
    func setStackedDetent(_ detent: PresentationDetent, at depth: Int) {
        guard stackedEntries.indices.contains(depth) else { return }
        stackedEntries[depth].detent = detent
    }

    /// Bounds-checked accessor for the stacked route at `depth`.
    /// Returns `nil` when `depth` is past the current pile.
    func stackedRoute(at depth: Int) -> Route? {
        stackedEntries.indices.contains(depth) ? stackedEntries[depth].route : nil
    }

    /// Bounds-checked accessor for the detent at `depth`. Returns `fallback`
    /// when `depth` is past the current pile (used during the brief window
    /// before SwiftUI installs the new layer).
    func stackedDetent(at depth: Int, fallback: PresentationDetent) -> PresentationDetent {
        stackedEntries.indices.contains(depth) ? stackedEntries[depth].detent : fallback
    }

    /// Clears the stacked layer and unwinds the content stack to its root.
    func popToRoot() {
        stackedEntries.removeAll()
        additionalRoutes.removeAll()
        currentDetent = root.detentConfiguration.initialDetent
    }
}
