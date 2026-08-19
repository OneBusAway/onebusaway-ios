//
//  StopTripSpacing.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics

/// Spacing table for the new stop and trip screens. Compact values are the
/// opt-in space-saving mode (#1278); regular values are the layout those
/// screens shipped with.
///
/// Accessibility-size stacked layouts **do** consult this table: the outer
/// stacks in `DepartureRowView`, `GroupedListView`, and `TripCardView` wrap
/// the AX branch, so compact tightens those layouts too. Tappable trip-stop
/// rows keep a 44pt minimum height regardless.
enum StopTripSpacing {
    /// Interior `VStack` under a route badge / headsign block.
    static func stack(_ compact: Bool) -> CGFloat { compact ? 1 : 3 }

    /// Badge-to-copy `HStack` on a departure row or trip card.
    static func hStack(_ compact: Bool) -> CGFloat { compact ? 8 : 13 }

    /// Trip header card's outer `VStack`.
    static func card(_ compact: Bool) -> CGFloat { compact ? 6 : 10 }

    /// Trip page's scroll content `VStack` (card, then stop list).
    static func tripPage(_ compact: Bool) -> CGFloat { compact ? 8 : 14 }

    /// Vertical padding inside one trip-stop timeline row.
    static func stopRowVertical(_ compact: Bool) -> CGFloat { compact ? 6 : 11 }

    /// Minimum height of a tappable trip-stop row. Compact padding would
    /// otherwise drop the hit target under 44pt.
    static let stopRowMinHeight: CGFloat = 44

    /// Padding around the trip header card.
    static func cardPadding(_ compact: Bool) -> CGFloat { compact ? 10 : 14 }
}
