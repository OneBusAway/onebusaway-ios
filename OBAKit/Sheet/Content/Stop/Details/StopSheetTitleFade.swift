//
//  StopSheetTitleFade.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics

/// Maps scroll position to how far the stop sheet's pinned title has faded in,
/// 0 (invisible, the header still names the stop) through 1 (fully in).
///
/// A pure function rather than logic inside the view, both so it can be tested
/// and so the feedback-loop hazard has one obvious home.
///
/// **Nothing downstream of this value may touch layout.** An earlier design
/// shrank a `safeAreaInset` as this rose, and it oscillated — the inset shifted
/// the offset, which changed progress, which resized the inset — until the main
/// thread was pegged and the app stopped responding. Two things keep that fixed:
/// callers pass `contentOffset.y + contentInsets.top`, a sum that holds steady
/// when an inset changes, and this drives opacity only. The sheet's chrome is
/// two fixed-height insets — the top bar and the action row — for the same
/// reason. See the note in `StopDetailsSheetView.sheetBody(proxy:)`.
nonisolated enum StopSheetTitleFade {

    /// - Parameters:
    ///   - scrollOffset: `contentOffset.y + contentInsets.top` — distance
    ///     scrolled from the top, invariant to inset changes.
    ///   - fadeDistance: the distance over which the fade completes. A plain
    ///     constant is correct here — a fade has no real geometry to stay
    ///     registered with, which is exactly why it is safe.
    /// - Returns: progress clamped to `0...1`; `0` when there is no distance to
    ///   fade over.
    static func progress(scrollOffset: CGFloat, fadeDistance: CGFloat) -> CGFloat {
        guard fadeDistance > 0 else { return 0 }
        return min(max(scrollOffset / fadeDistance, 0), 1)
    }
}
