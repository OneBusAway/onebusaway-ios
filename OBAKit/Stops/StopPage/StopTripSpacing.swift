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
/// the AX branch, so compact tightens those layouts too. A compact trip-stop
/// row is its own tap target — smaller than 44pt at default Dynamic Type.
/// That is the trade the rider chose by opting in.
enum StopTripSpacing {
    /// Interior `VStack` under a route badge / headsign block.
    static func stack(_ compact: Bool) -> CGFloat { compact ? 1 : 3 }

    /// Badge-to-copy `HStack` on a departure row or trip card.
    static func hStack(_ compact: Bool) -> CGFloat { compact ? 8 : 13 }

    /// Trip header card's outer `VStack`.
    static func card(_ compact: Bool) -> CGFloat { compact ? 6 : 10 }

    /// Trip page's scroll content `VStack` (card, then stop list).
    static func tripPage(_ compact: Bool) -> CGFloat { compact ? 8 : 14 }

    /// Vertical padding inside one trip-stop timeline row. Compact 6pt
    /// makes a default-size subheadline row ~32pt; the tap target is that
    /// row, not a 44pt overlay. A 44pt slop on a 32pt `LazyVStack` row
    /// overlaps the neighbour and opens the wrong stop.
    static func stopRowVertical(_ compact: Bool) -> CGFloat { compact ? 6 : 11 }

    /// Padding around the trip header card.
    static func cardPadding(_ compact: Bool) -> CGFloat { compact ? 10 : 14 }
}
