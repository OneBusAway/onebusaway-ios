//
//  ScrollToTopVisibility.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics

/// Decides whether the stop sheet's scroll-to-top button is showing.
///
/// A pure function rather than logic inside the view, so the rule can be tested:
/// the overlay's rendering and the scroll itself both need a real scroll view and
/// are verified by hand.
///
/// One viewport is the threshold because it is both the convention (Safari, the
/// App Store) and its own content gate — a stop with a handful of departures
/// cannot scroll a full screen, so the button never appears there and no separate
/// cell-count rule is needed.
nonisolated enum ScrollToTopVisibility {

    /// - Parameters:
    ///   - scrollOffset: distance scrolled from the top, as
    ///     `contentOffset.y + contentInsets.top`. Negative while rubber-banding
    ///     above the top.
    ///   - viewportHeight: the scroll view's container height. Zero before the
    ///     first layout pass.
    /// - Returns: `true` once the rider has scrolled more than one viewport.
    static func shouldShow(scrollOffset: CGFloat, viewportHeight: CGFloat) -> Bool {
        guard viewportHeight > 0 else { return false }
        return scrollOffset > viewportHeight
    }
}
