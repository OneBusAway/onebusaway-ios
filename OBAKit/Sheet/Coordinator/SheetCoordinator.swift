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
class SheetCoordinator<Route: SheetRouteable>: ObservableObject {

    // MARK: - Content-swap layer (base sheet)

    @Published private(set) var routeStack: [Route]
    @Published var currentDetent: PresentationDetent

    var currentRoute: Route { routeStack.last! }
    var currentDetents: Set<PresentationDetent> { currentRoute.detentConfiguration.detents }
    var canPop: Bool { routeStack.count > 1 || !stackedRoutes.isEmpty }

    // MARK: - Stacked layer

    /// One physical sheet per entry; index 0 is the closest to the base sheet,
    /// `last` is the frontmost. Empty when no stacked sheets are presented.
    @Published var stackedRoutes: [Route] = []

    /// Detents parallel to `stackedRoutes`. `stackedDetents[i]` selects the
    /// current detent of the sheet at depth `i`.
    @Published var stackedDetents: [PresentationDetent] = []

    // MARK: - Init

    init(root: Route) {
        routeStack = [root]
        currentDetent = root.detentConfiguration.initialDetent
    }

    // MARK: - Unified navigation

    /// Pushes a route on whichever layer it prefers.
    /// Stacked routes append a new physical sheet over the previous one;
    /// content-swap routes append to the base content stack.
    func push(_ route: Route) {
        if route.prefersStacking {
            stackedRoutes.append(route)
            stackedDetents.append(route.detentConfiguration.initialDetent)
        } else {
            routeStack.append(route)
            currentDetent = route.detentConfiguration.initialDetent
        }
    }

    /// Pops the top of whichever layer is on top: frontmost stacked sheet if
    /// any, otherwise the content-stack top. No-op at root.
    func pop() {
        if !stackedRoutes.isEmpty {
            stackedRoutes.removeLast()
            stackedDetents.removeLast()
            return
        }
        guard routeStack.count > 1 else { return }
        routeStack.removeLast()
        currentDetent = currentRoute.detentConfiguration.initialDetent
    }

    /// Removes every stacked sheet at or above the given depth. Called by the
    /// container when the OS dismisses a sheet (drag-down) so the array stays
    /// in sync with what's actually on screen.
    func truncateStacked(toDepth depth: Int) {
        guard depth >= 0, depth < stackedRoutes.count else { return }
        stackedRoutes.removeSubrange(depth...)
        stackedDetents.removeSubrange(depth...)
    }

    /// Clears the stacked layer and unwinds the content stack to its root.
    func popToRoot() {
        stackedRoutes.removeAll()
        stackedDetents.removeAll()
        routeStack = [routeStack[0]]
        currentDetent = currentRoute.detentConfiguration.initialDetent
    }
}
