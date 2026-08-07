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
/// and so the feedback-loop hazard has one obvious home.
///
/// The sheet's chrome deliberately does **not** resize with this value: the top
/// bar is a fixed-height `safeAreaInset` and the action row is an overlay. An
/// earlier design shrank the inset as progress rose, and that oscillated — the
/// inset shifted the offset, which changed progress, which resized the inset —
/// until the main thread was pegged. Two things keep it broken today: callers
/// pass `contentOffset.y + contentInsets.top`, a sum that holds steady when the
/// inset changes, and nothing downstream of this value touches layout. See the
/// note in `StopDetailsSheetView.sheetBody(proxy:)`.
nonisolated enum StopSheetHeaderCollapse {

    /// - Parameters:
    ///   - scrollOffset: `contentOffset.y + contentInsets.top` — distance
    ///     scrolled from the top, invariant to inset changes.
    ///   - collapsibleHeight: the distance over which the collapse completes.
    ///     A measured height where the result drives something that must line
    ///     up with real geometry; a plain constant is fine — and is what
    ///     `StopDetailsSheetView.titleFadeDistance` passes — where it only
    ///     drives opacity, since a fade has nothing to stay registered with.
    /// - Returns: progress clamped to `0...1`; `0` when there is nothing to
    ///   collapse.
    static func progress(scrollOffset: CGFloat, collapsibleHeight: CGFloat) -> CGFloat {
        guard collapsibleHeight > 0 else { return 0 }
        return min(max(scrollOffset / collapsibleHeight, 0), 1)
    }
}
