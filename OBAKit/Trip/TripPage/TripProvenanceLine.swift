//
//  TripProvenanceLine.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The trip card's footer: which route, which vehicle, and how fresh the
/// position is — "RapidRide H · Vehicle 6821 · position updated 12s ago".
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
    static func text(routeName: String?, vehicleLabel: String?, freshness: String?) -> String? {
        let clauses = [routeName, vehicleLabel, freshness]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        guard !clauses.isEmpty else { return nil }
        return clauses.joined(separator: separator)
    }
}
