//
//  StopPageListBuilder.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The list-shape abstraction over `ArrivalDeparture` that the Stop page's
/// pure transforms operate on; production code passes `ArrivalDeparture`,
/// tests pass lightweight stubs (the real type only decodes from JSON).
protocol DepartureListEntry {
    var id: String { get }
    var routeID: RouteID { get }
    var arrivalDepartureMinutes: Int { get }
    var temporalState: TemporalState { get }
}

extension ArrivalDeparture: DepartureListEntry {}

/// Pure transforms shared by both Stop page list modes. Both modes are
/// projections of the same filtered departure list (spec §3); callers apply
/// `filter(preferences:)` for hidden routes before calling in.
enum StopPageListBuilder {

    // MARK: - Chronological

    struct ChronologicalPartition<D: DepartureListEntry> {
        /// Already departed. Rendered dimmed, no strikethrough (§4.2).
        let past: [D]
        /// Upcoming, but arriving sooner than the user can walk to the stop.
        /// Rendered dimmed + struck-through (§4.2).
        let missed: [D]
        /// Catchable on foot: `arrivalDepartureMinutes >= walkMinutes` (§4.5).
        let reachable: [D]
    }

    static func chronologicalPartition<D: DepartureListEntry>(_ departures: [D], walkMinutes: Int?) -> ChronologicalPartition<D> {
        let sorted = departures.sorted { $0.arrivalDepartureMinutes < $1.arrivalDepartureMinutes }
        let past = sorted.filter { $0.temporalState == .past }
        let upcoming = sorted.filter { $0.temporalState != .past }

        guard let walkMinutes else {
            return ChronologicalPartition(past: past, missed: [], reachable: upcoming)
        }

        let missed = upcoming.filter { $0.arrivalDepartureMinutes < walkMinutes }
        let reachable = upcoming.filter { $0.arrivalDepartureMinutes >= walkMinutes }
        return ChronologicalPartition(past: past, missed: missed, reachable: reachable)
    }

    // MARK: - Grouped ("By route")

    struct RouteGroup<D: DepartureListEntry> {
        let routeID: RouteID
        /// Time-sorted; never empty. `[0]` is the card-header "next" departure.
        let departures: [D]

        var next: D { departures[0] }
        var upcoming: [D] { Array(departures.dropFirst()) }
        /// The small status-tinted pills
        var chips: [D] { Array(departures.dropFirst().prefix(3)) }
    }

    /// Groups by route, preserving first-appearance order after the time sort,
    /// so routes rank by their soonest departure (§4.9). Past departures are
    /// excluded — grouped mode has no past block.
    static func routeGroups<D: DepartureListEntry>(_ departures: [D]) -> [RouteGroup<D>] {
        let sorted = departures
            .filter { $0.temporalState != .past }
            .sorted { $0.arrivalDepartureMinutes < $1.arrivalDepartureMinutes }

        var order: [RouteID] = []
        var buckets: [RouteID: [D]] = [:]
        for departure in sorted {
            if buckets[departure.routeID] == nil { order.append(departure.routeID) }
            buckets[departure.routeID, default: []].append(departure)
        }
        return order.map { RouteGroup(routeID: $0, departures: buckets[$0]!) }
    }
}
