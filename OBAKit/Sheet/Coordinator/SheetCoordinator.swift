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

    /// Whether the latest change to the routes was `popToRoot()`, which only the
    /// app does (a region change, a deep link), rather than the rider closing a
    /// sheet with its close button or a drag. The map's feedback prompt asks only
    /// after the rider's own close.
    private(set) var lastChangeWasPopToRoot = false

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

    /// The stacked layer whose sheets `open(_:from:)` closed to go back to a route
    /// already open further down, until that layer's dismissal claims it.
    /// See `claimUnwindFocus(atDepth:)`.
    ///
    /// Not `@Published`: nothing draws from it, and publishing it would redraw
    /// every layer for a value only one of them reads, once.
    private(set) var unwindFocusDepth: Int?

    /// The base sheet's detent when the first stacked sheet opened over it, to go
    /// back to when the last one closes. `nil` with nothing stacked.
    ///
    /// One sheet at a time (HIG, Sheets): while a stacked sheet is up, the base
    /// sheet rests at its initial detent, which for home is the collapsed search
    /// field, so a stop opened from an expanded home sheet doesn't sit over a
    /// second full sheet of lists. Closing the stop puts home back as it was.
    private(set) var baseDetentBeforeStacking: PresentationDetent?
    /// The base route `baseDetentBeforeStacking` belongs to.
    private var baseRouteBeforeStacking: Route?

    /// Every route on screen: the base sheet's stack from its root up, then the
    /// stacked sheets from the bottom up.
    var allRoutes: [Route] { routeStack + stackedRoutes }

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
    /// A stacked route that allows interactive dismissal leaves drag-down to
    /// the OS, and `truncateStacked` keeps storage in sync with that gesture. A
    /// stacked route that locks it (the stop sheet, #1751) must offer its own
    /// way out that calls `pop()`, or the rider has none.
    func push(_ route: Route) {
        lastChangeWasPopToRoot = false
        if route.prefersStacking {
            // A sheet opening on top takes VoiceOver itself, so an unwind still
            // closing beneath it has no focus left to move.
            unwindFocusDepth = nil
            if stackedEntries.isEmpty {
                restBaseSheet()
            }
            stackedEntries.append(StackedEntry(route: route, detent: route.detentConfiguration.initialDetent))
        } else {
            additionalRoutes.append(route)
            currentDetent = route.detentConfiguration.initialDetent
        }
    }

    /// Pops the top of whichever layer is on top: frontmost stacked sheet if
    /// any, otherwise the content-stack top. No-op at root.
    func pop() {
        lastChangeWasPopToRoot = false
        if !stackedEntries.isEmpty {
            stackedEntries.removeLast()
            restoreBaseSheetIfUncovered()
            return
        }
        guard !additionalRoutes.isEmpty else { return }
        additionalRoutes.removeLast()
        currentDetent = currentRoute.detentConfiguration.initialDetent
    }

    /// Opens `route` from the stacked sheet showing `source`, where a tap inside that
    /// sheet should land.
    ///
    /// If `route` is already open further down, the sheets above it close and the
    /// rider goes back to it, rather than getting a second copy or nothing at all.
    /// Otherwise any sheets above `source` close and `route` goes on top of it, so
    /// Back returns to `source`. A `source` that is no longer in the pile changes
    /// nothing below, and `route` is pushed on top.
    func open(_ route: Route, from source: Route) {
        lastChangeWasPopToRoot = false
        if let existing = stackedEntries.lastIndex(where: { $0.route == route }) {
            let closingDepth = existing + 1
            // Already on top: nothing closes, so there is no dismissal to claim this.
            if closingDepth < stackedEntries.count {
                unwindFocusDepth = closingDepth
            }
            truncateStacked(toDepth: closingDepth)
            return
        }
        if let sourceDepth = stackedEntries.lastIndex(where: { $0.route == source }) {
            truncateStacked(toDepth: sourceDepth + 1)
        }
        push(route)
    }

    /// Selects a route from a map pin interaction, opening over the current sheet or
    /// unwinding if already present, while avoiding duplicate sheets on repeated selection.
    func selectFromMap(_ route: Route) {
        restoreRoute(route)
    }

    /// Navigates to a route, unwinding to an existing entry if already presented or opening
    /// over the current sheet, consolidating map-selection and panel navigation paths.
    func restoreRoute(_ route: Route) {
        if route.prefersStacking {
            if stackedRoutes.last == route {
                return
            }
            lastChangeWasPopToRoot = false
            if let existing = stackedEntries.lastIndex(where: { $0.route == route }) {
                let closingDepth = existing + 1
                if closingDepth < stackedEntries.count {
                    unwindFocusDepth = closingDepth
                }
                truncateStacked(toDepth: closingDepth)
                return
            }
            if let current = stackedRoutes.last {
                open(route, from: current)
            } else {
                push(route)
            }
        } else {
            if route == root {
                popToRoot()
                return
            }
            if currentRoute == route, stackedEntries.isEmpty {
                return
            }
            lastChangeWasPopToRoot = false
            if !stackedEntries.isEmpty {
                truncateStacked(toDepth: 0)
                if currentRoute == route {
                    return
                }
            }
            if let existing = additionalRoutes.lastIndex(where: { $0 == route }) {
                additionalRoutes.removeSubrange((existing + 1)...)
                currentDetent = currentRoute.detentConfiguration.initialDetent
                return
            }
            push(route)
        }
    }

    /// Removes every stacked sheet at or above the given depth. Called by the
    /// container when the OS dismisses a sheet (drag-down) so storage stays in
    /// sync with what's actually on screen.
    func truncateStacked(toDepth depth: Int) {
        lastChangeWasPopToRoot = false
        guard depth >= 0, depth < stackedEntries.count else { return }
        stackedEntries.removeSubrange(depth...)
        restoreBaseSheetIfUncovered()
    }

    /// Moves the base sheet to its initial detent for a stacked sheet opening
    /// over it, remembering where it was; see `baseDetentBeforeStacking`.
    private func restBaseSheet() {
        let resting = currentRoute.detentConfiguration.initialDetent
        guard currentDetent != resting else { return }
        baseDetentBeforeStacking = currentDetent
        baseRouteBeforeStacking = currentRoute
        currentDetent = resting
    }

    /// Puts the base sheet back where it was once nothing is stacked over it,
    /// if it's still showing the route it was rested on.
    private func restoreBaseSheetIfUncovered() {
        guard stackedEntries.isEmpty, let detent = baseDetentBeforeStacking else { return }
        let route = baseRouteBeforeStacking
        baseDetentBeforeStacking = nil
        baseRouteBeforeStacking = nil
        guard route == currentRoute, currentDetents.contains(detent) else { return }
        currentDetent = detent
    }

    /// Updates the stored detent for the stacked sheet at `depth`.
    func setStackedDetent(_ detent: PresentationDetent, at depth: Int) {
        guard stackedEntries.indices.contains(depth) else { return }
        stackedEntries[depth].detent = detent
    }

    /// Moves the topmost stacked sheet whose route matches `predicate` to `detent`.
    ///
    /// Depth-free on purpose: a sheet's own content knows *which route it is* but has
    /// no way to learn its index in the pile, and that content is exactly what needs to
    /// resize itself in response to something happening inside it.
    ///
    /// Refuses a detent the route doesn't declare — `presentationDetents(_:selection:)`
    /// ignores a selection outside its set, so writing one would leave stored state
    /// disagreeing with what is on screen. Returns whether the move was applied.
    @discardableResult
    func setStackedDetent(
        _ detent: PresentationDetent,
        forTopmostRouteMatching predicate: (Route) -> Bool
    ) -> Bool {
        guard let depth = stackedEntries.lastIndex(where: { predicate($0.route) }),
              stackedEntries[depth].route.detentConfiguration.detents.contains(detent) else {
            return false
        }
        stackedEntries[depth].detent = detent
        return true
    }

    /// Whether another stacked sheet is presented over the one at `depth`.
    ///
    /// The container keeps a covered sheet from being swiped away. A sheet on top
    /// that lets touches through (a `.medium` trip sheet, say) leaves the one under
    /// it draggable, and swiping that one away left the sheet on top on screen with
    /// no route behind it in the pile.
    func isStackedSheetCovered(atDepth depth: Int) -> Bool {
        depth < stackedEntries.count - 1
    }

    /// Whether the dismissal of the stacked layer at `depth` was an unwind by
    /// `open(_:from:)`, after which VoiceOver should move to the sheet revealed.
    /// `true` once per unwind: claiming it clears it.
    ///
    /// Going back to a sheet further down closes every sheet above it at once, and
    /// UIKit leaves focus wherever it lands — possibly on a sheet that is closing.
    /// A sheet the rider drags away is left alone: UIKit returns focus to the
    /// control that opened it, which is better than the top of the sheet revealed.
    func claimUnwindFocus(atDepth depth: Int) -> Bool {
        guard unwindFocusDepth == depth else { return false }
        unwindFocusDepth = nil
        return true
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
        lastChangeWasPopToRoot = true
        unwindFocusDepth = nil
        baseDetentBeforeStacking = nil
        baseRouteBeforeStacking = nil
        stackedEntries.removeAll()
        additionalRoutes.removeAll()
        currentDetent = root.detentConfiguration.initialDetent
    }
}

// MARK: - Returning to a stacked sheet

/// When a screen that is *itself* a stacked sheet has become visible again
/// because something on top of it went away.
///
/// A stacked sheet is never removed from the view hierarchy while another sheet
/// covers it, so `.task` and `.onAppear` fire exactly once no matter how many
/// times the user comes back to it. Any screen whose contents can go stale
/// underneath — the Recent Stops index, whose store is rewritten by the very act
/// of viewing a stop from it — has to notice the return some other way.
///
/// Kept as a pure function so the rule is assertable without a sheet stack, in
/// the same spirit as `NearbyCoordinateResolver`.
nonisolated enum StackedSheetReturn {

    /// Whether a change in stacked depth means a sheet at *any* depth has just
    /// been uncovered.
    ///
    /// Keyed on the depth decreasing rather than reaching zero: a stacked sheet
    /// is itself part of the count, so the stack never empties while one is on
    /// screen. `HomeSheetView` can watch for empty because it sits below the
    /// stacked layer entirely — same intent, different depth. Getting this
    /// wrong fails silently, which is why it has a name and a test.
    ///
    /// - Parameters:
    ///   - previousDepth: `stackedRoutes.count` before the change.
    ///   - depth: `stackedRoutes.count` after it.
    static func wasUncovered(previousDepth: Int, depth: Int) -> Bool {
        depth < previousDepth
    }
}
