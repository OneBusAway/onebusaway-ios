//
//  StopCollapsedDetent.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Synchronization

/// The stop sheet's smallest detent: the pinned top bar (the stop's actions and
/// Close) and the stop's name block under it, and no more (#1751).
///
/// The stop sheet can't be swiped away; only Close dismisses it. Dragging it
/// down stops here instead, which gives the rider the map back without losing
/// the stop. It is the panel's counterpart of `StopSheetPresenter`'s `.tip`.
///
/// Fitted to the sheet as laid out, measured by `StopDetailsSheetView`, so it
/// holds at any text size, the way `HomeCollapsedDetent` fits the home sheet's
/// header. Being a type, it stays the same detent as its height changes, so the
/// coordinator's stored selection keeps matching.
nonisolated struct StopCollapsedDetent: CustomPresentationDetent {
    nonisolated struct Measurements: Sendable {
        /// The pinned top bar, as laid out.
        var topBarHeight: CGFloat?
        /// The header's name and stop code/direction, with the header's padding.
        var titleBlockHeight: CGFloat?
    }

    /// Set as the sheet is laid out. Stored here rather than in the environment
    /// for the reason `HomeCollapsedDetent.measured` is: a custom detent's
    /// `Context` carries only the system's environment values. Only the
    /// uncovered stop sheet writes it (`StopDetailsSheetView`), so a stop stacked
    /// over another sizes the detent from its own name.
    static let measured = Mutex(Measurements())

    /// About as short as iOS 26 will draw a floating sheet without narrowing
    /// it and lifting it off the bottom; see `AppSheetRoute.homeCollapsedHeight`.
    static let minimumHeight: CGFloat = 100

    /// The height before the sheet has been measured: the top bar and a
    /// one-line name at the default text size.
    static let estimatedHeight: CGFloat = 135

    /// The most of `maxDetentValue` collapsed may take, so it stays below
    /// `.medium` and a drag down from there still has somewhere to go.
    static let maximumFraction: CGFloat = 0.45

    static func height(in context: Context) -> CGFloat? {
        height(measured.withLock { $0 }, maxDetentValue: context.maxDetentValue)
    }

    static func height(_ measurements: Measurements, maxDetentValue: CGFloat) -> CGFloat {
        let height = collapsedHeight(topBarHeight: measurements.topBarHeight, titleBlockHeight: measurements.titleBlockHeight)
        return min(height, max(minimumHeight, maxDetentValue * maximumFraction))
    }

    /// The top bar and the name block, never less than `minimumHeight`; the
    /// estimate until both have been measured.
    static func collapsedHeight(topBarHeight: CGFloat?, titleBlockHeight: CGFloat?) -> CGFloat {
        guard let topBarHeight, let titleBlockHeight else { return estimatedHeight }
        return max(topBarHeight + titleBlockHeight, minimumHeight)
    }
}
