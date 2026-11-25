//
//  TripProvenanceLine.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The trip card's footer: which route, which trip, which vehicle, and how fresh
/// the position is — "RapidRide H · Vehicle 6821 · position updated 12s ago".
///
/// Every clause is optional in practice. A schedule-only trip has no vehicle and
/// no position age; some feeds omit the route's long name. Joining these by
/// interpolation is what produces the stray separators this exists to prevent,
/// so the assembly lives in one tested place.
nonisolated enum TripProvenanceLine {

    /// The separator from the design. A middle dot with hair spacing, matching
    /// the one `DepartureRowView` puts between time and status.
    private static let separator = " · "

    /// - Returns: `nil` when there is nothing to say, so the caller can drop the
    ///   label rather than render an empty row that still takes vertical space.
    static func text(routeName: String?, tripLabel: String? = nil, vehicleLabel: String?, freshness: String?) -> String? {
        let clauses = [routeName, tripLabel, vehicleLabel, freshness]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        guard !clauses.isEmpty else { return nil }
        return clauses.joined(separator: separator)
    }

    /// The trip's public short name, such as a Sounder train number: "Trip 1519".
    /// `nil` for the many feeds that leave it out, so the clause disappears.
    @MainActor static func tripLabel(shortName: String?) -> String? {
        guard let shortName = shortName?.trimmingCharacters(in: .whitespacesAndNewlines), !shortName.isEmpty else { return nil }
        return String(format: OBALoc("trip_page.trip_short_name_fmt", value: "Trip %@", comment: "Identifies a trip by its public short name on the trip page, such as a commuter rail train number, e.g. 'Trip 1519'."), shortName)
    }

    /// How old the vehicle's position is: "position updated 12 sec. ago", or, while
    /// the map is estimating where the vehicle is now, "estimated position, updated
    /// 12 sec. ago". `nil` with no update to measure from.
    @MainActor static func freshness(lastUpdate: Date?, isEstimated: Bool, relativeTo now: Date) -> String? {
        guard let lastUpdate else { return nil }
        let age = RelativeDateTimeFormatter.vehiclePositionAge.localizedString(for: lastUpdate, relativeTo: now)
        let format = isEstimated
            ? OBALoc("trip_page.position_estimated_fmt", value: "estimated position, updated %@", comment: "How stale the vehicle's last reported position is, when the map shows where the vehicle is estimated to be now rather than where it last reported. %@ is a relative time like '12s ago'.")
            : OBALoc("trip_page.position_updated_fmt", value: "position updated %@", comment: "How stale the vehicle's reported position is. %@ is a relative time like '12s ago'.")
        return String(format: format, age)
    }

}

extension RelativeDateTimeFormatter {
    /// How old a vehicle's reported position is, abbreviated ("12s ago"): the trip
    /// card's provenance line and the map's vehicle callout. Shared so the two
    /// can't drift apart. Static: building one per callout is measurably wasteful.
    @MainActor static let vehiclePositionAge: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        // `.abbreviated` ("12s ago"), not `.short` ("12 sec. ago") — the design's
        // freshness line, and short enough not to wrap under the countdown.
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
