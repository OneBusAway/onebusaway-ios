//
//  TripETADistance.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// The trip card's "1.2 mi away · 3 stops" line: how far the tracked vehicle
/// still is from the rider's stop.
///
/// The feed keeps counting after the vehicle reaches the stop —
/// `distanceFromStop` and `numberOfStopsAway` go to zero and then negative
/// (fixtures carry -1833.69 m with -9 stops) — so neither value can be
/// formatted as-is.
nonisolated struct TripETADistance: Equatable {
    let text: String
    let accessibilityText: String

    /// - Parameter isPredicted: The feed's `predicted` flag. Without it the
    ///   distance is the server's schedule-based guess at a vehicle position,
    ///   and the card's real-time gate (`DepartureStatus`) forbids presenting
    ///   schedule data as a tracked vehicle.
    /// - Returns: `nil` when there is nothing truthful to show: schedule-only
    ///   data, or a vehicle that has already passed the stop.
    static func make(
        distanceMeters: Double,
        stopsAway: Int,
        isPredicted: Bool,
        formatter: MKDistanceFormatter,
        locale: Locale = .current
    ) -> TripETADistance? {
        guard isPredicted, distanceMeters.isFinite, distanceMeters >= 0, stopsAway >= 0 else {
            return nil
        }

        guard distanceMeters > 0, stopsAway > 0 else {
            let arriving = OBALoc(
                "trip_page.card.arriving_at_stop",
                value: "Arriving at your stop",
                comment: "Trip card line shown in place of the vehicle's distance once its next stop is the rider's stop."
            )
            return TripETADistance(text: arriving, accessibilityText: arriving)
        }

        let distance = formatter.string(fromDistance: distanceMeters)

        let fmt = OBALoc(
            "trip_page.card.distance_stops_fmt",
            value: "%1$@ away · %2$d stops",
            comment: "Trip card line: how far the vehicle is from the rider's stop. %1$@ is a distance like '1.2 mi', %2$d the number of stops in between. Plural forms live in Localizable.stringsdict; this value is only the not-found fallback."
        )
        let a11yFmt = OBALoc(
            "trip_page.card.distance_stops_a11y_fmt",
            value: "%1$@ away, %2$d stops away",
            comment: "VoiceOver version of the trip card's distance line. %1$@ is a distance like '1.2 mi', %2$d the number of stops in between. Plural forms live in Localizable.stringsdict; this value is only the not-found fallback."
        )

        // The locale must be explicit: see StopPageAccessibilityCopy — the no-locale
        // overload makes Slavic `few`/`many` unreachable.
        return TripETADistance(
            text: String(format: fmt, locale: locale, distance, stopsAway),
            accessibilityText: String(format: a11yFmt, locale: locale, distance, stopsAway)
        )
    }

    static func make(departure: ArrivalDeparture, formatter: MKDistanceFormatter) -> TripETADistance? {
        make(
            distanceMeters: departure.distanceFromStop,
            stopsAway: departure.numberOfStopsAway,
            isPredicted: departure.predicted,
            formatter: formatter
        )
    }
}
