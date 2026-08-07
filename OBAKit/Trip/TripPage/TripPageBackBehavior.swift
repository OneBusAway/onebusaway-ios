//
//  TripPageBackBehavior.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// What the trip page's Back row should do, given the stack it finds itself in.
///
/// The page has two presentations and they need opposite gestures. Pushed from
/// the Stop page it sits on an existing navigation stack and pops. Presented
/// from the map sheet — which has no stack of its own, so
/// `StopPageActionPresenter.showTripPage` wraps it in a fresh
/// `UINavigationController` — it is the *root* of that stack, where
/// `popViewController` returns nil and does nothing.
///
/// That second case shipped as a Back button the rider could see and press to no
/// effect, on a modal that also had `isModalInPresentation = true` (no swipe)
/// and a hidden navigation bar (so the Done button
/// `presentWrappedInNavigation` installs was invisible) — three affordances,
/// none of them a way out.
///
/// A plain value so the decision is testable without presenting anything: the
/// precedent set by `StopPageContent` and `ScrollToTopVisibility`.
nonisolated enum TripPageBackBehavior: Equatable {
    /// There is something underneath on the same stack; go back to it.
    case pop
    /// This page is the root of its own stack, or has no stack at all. The only
    /// way out is to dismiss whatever is presenting it.
    case dismiss

    /// - Parameter navigationStackDepth: how many controllers the page's
    ///   `navigationController` holds, or `0` when it has none.
    static func forStackDepth(_ navigationStackDepth: Int) -> TripPageBackBehavior {
        navigationStackDepth > 1 ? .pop : .dismiss
    }
}
