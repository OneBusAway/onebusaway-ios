//
//  DepartureAccessibility.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Assembles the spoken description of a departure *row* — the Stop page's flat
/// and grouped lists, and the Trip page's header card.
///
/// `RouteBadgeView`, `CountdownView` and `DepartureTimeText` all mark themselves
/// `.accessibilityHidden(true)`, on the contract that whatever composes them
/// re-speaks their content. Nothing enforces that contract, and it has already
/// been broken once: `TripCardView` shipped with no accessibility modifiers at
/// all, so a VoiceOver user could not reach the route number, the countdown or
/// the departure time — the three facts the trip page exists to convey.
///
/// `DepartureRowView` and `GroupedListView` had each written this clause list
/// out longhand, with their own copy of the comment explaining the ordering
/// rule. This owns the order and the optional clauses; callers supply only the
/// leading sentence, which is the part that genuinely differs between them.
///
/// Deliberately not the *only* builder of departure speech in the app:
/// `GroupedListView.groupAccessibilityLabel` summarises a whole route group,
/// and `Formatters+BookmarkArrival`, `TripLiveActivityCardView` and the widget's
/// `WidgetRowView` each speak a departure in a context with different rules.
/// Those are separate sentences, not call sites this should absorb.
enum DepartureAccessibility {

    /// - Parameters:
    ///   - identity: The leading sentence — route, headsign, and how far off the
    ///     departure is. Callers own this because the verb differs: a list row
    ///     "departs", the trip card "arrives", a past row "departed".
    ///   - departure: Supplies the occupancy clause, when the status allows one.
    ///   - status: Gates occupancy. A schedule-only departure reports no crowding.
    ///   - timeDisplay: Supplies the clock time. Spoken because the strikethrough
    ///     that carries a delay on screen is inaudible.
    ///   - extraClauses: Appended last — an alarm, a provenance line, a
    ///     "likely missed" warning.
    static func label(
        identity: String,
        departure: ArrivalDeparture,
        status: DepartureStatus,
        timeDisplay: DepartureTimeDisplay,
        extraClauses: [String] = []
    ) -> String {
        var clauses = [identity, timeDisplay.accessibilityTimeDescription]

        if status.showsOccupancy, let occupancy = departure.occupancyStatus, occupancy != .unknown {
            clauses.append(OccupancyBadge.localizedDescription(occupancy))
        }

        clauses.append(contentsOf: extraClauses)

        return clauses.joined(separator: ", ")
    }
}
