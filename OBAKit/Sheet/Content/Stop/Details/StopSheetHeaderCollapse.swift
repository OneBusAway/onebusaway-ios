//
//  StopSheetHeaderCollapse.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics

/// Maps scroll position to how far the stop sheet's map header has collapsed,
/// 0 (fully expanded) through 1 (gone).
///
/// A pure function rather than logic inside the view, both so it can be tested
/// and so the feedback-loop hazard has one obvious home. The chrome lives in a
/// `safeAreaInset` whose height shrinks as this value rises; if progress were
/// derived from `contentOffset.y` alone, shrinking the inset would shift the
/// offset, which would change progress, which would resize the inset again.
/// Callers pass `contentOffset.y + contentInsets.top`, a sum that holds steady
/// when the inset changes, which breaks the loop.
nonisolated enum StopSheetHeaderCollapse {

    /// - Parameters:
    ///   - scrollOffset: `contentOffset.y + contentInsets.top` — distance
    ///     scrolled from the top, invariant to inset changes.
    ///   - collapsibleHeight: the header's laid-out height, measured rather
    ///     than assumed: it is `@ScaledMetric` and grows further when route
    ///     chips wrap, so a hard-coded constant would mis-collapse at most
    ///     Dynamic Type sizes.
    /// - Returns: progress clamped to `0...1`; `0` when there is nothing to
    ///   collapse.
    static func progress(scrollOffset: CGFloat, collapsibleHeight: CGFloat) -> CGFloat {
        guard collapsibleHeight > 0 else { return 0 }
        return min(max(scrollOffset / collapsibleHeight, 0), 1)
    }
}
