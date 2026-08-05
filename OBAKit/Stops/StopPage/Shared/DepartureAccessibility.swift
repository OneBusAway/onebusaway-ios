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

/// The one place that assembles a departure's spoken description.
///
/// `RouteBadgeView`, `CountdownView` and `DepartureTimeText` all mark themselves
/// `.accessibilityHidden(true)`, on the contract that whatever composes them
/// re-speaks their content. Nothing enforces that contract, and it has already
/// been broken once: `TripCardView` shipped with no accessibility modifiers at
/// all, so a VoiceOver user could not reach the route number, the countdown or
/// the departure time — the three facts the trip page exists to convey.
///
/// Three call sites had independently written the same clause list, each with
/// its own copy of the comment explaining the ordering rule. This owns the order
/// and the optional clauses; callers supply only the leading sentence, which is
/// the one part that genuinely differs between them.
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
