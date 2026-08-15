//
//  NearbyStopsIndexSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// One direction's worth of stops on the Nearby Stops index.
///
/// A plain value with a pure builder, so the grouping and search rules can be
/// asserted without standing up a view — the same reasoning behind
/// `RouteStopsRow.rows(from:)`.
nonisolated struct NearbyStopsIndexSection: Identifiable {
    let direction: Direction
    let title: String
    let stops: [Stop]

    /// `Direction` is unique per section, so its raw value is a stable id.
    var id: Int { direction.rawValue }

    /// Groups `stops` by direction, dropping anything that doesn't match
    /// `filter`. Sections come back in `Direction` order and are never empty.
    ///
    /// A nil, blank, or whitespace-only `filter` matches everything:
    /// `.searchable` hands the view an empty string the moment the field is
    /// focused, which must not blank the list.
    static func sections(stops: [Stop], filter: String?) -> [NearbyStopsIndexSection] {
        let query = String.nilifyBlankValue(
            filter?.localizedLowercase.trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? nil

        var grouped: [Direction: [Stop]] = [:]
        for stop in stops where stop.matchesQuery(query) {
            grouped[stop.direction, default: []].append(stop)
        }

        return grouped.keys.sorted().map { direction in
            NearbyStopsIndexSection(
                direction: direction,
                title: Formatters.adjectiveFormOfCardinalDirection(direction) ?? "",
                stops: grouped[direction] ?? []
            )
        }
    }
}
