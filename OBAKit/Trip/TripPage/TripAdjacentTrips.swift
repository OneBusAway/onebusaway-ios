//
//  TripAdjacentTrips.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The trips the same vehicle runs either side of this one: what the trip
/// "starts as", listed above its first stop, and what it "continues as", below
/// its last.
///
/// A vehicle runs a block of trips back to back, often on different routes, so
/// a rider who stays on board rides into the next one. OBA names the trips on
/// either side in the trip's schedule (`TripDetails.previousTrip` and `nextTrip`).
struct TripAdjacentTrips {

    enum Order {
        /// The trip the vehicle runs before this one.
        case previous
        /// The trip the vehicle runs after this one.
        case next
    }

    /// One row: which side of the trip it's on, and the trip it opens.
    struct Row {
        let order: Order
        let trip: Trip

        /// "Starts as 10 - Downtown Seattle", with the route and headsign the trip
        /// panel's rows showed.
        var title: String {
            let format = switch order {
            case .previous:
                OBALoc("trip_page.starts_as_fmt", value: "Starts as %@", comment: "Row on the trip page naming the trip the same vehicle runs just before this one. %@ is that trip's route and headsign, e.g. 'Starts as 10 - Downtown Seattle'.")
            case .next:
                OBALoc("trip_page.continues_as_fmt", value: "Continues as %@", comment: "Row on the trip page naming the trip the same vehicle runs next, which a rider who stays on board rides into. %@ is that trip's route and headsign, e.g. 'Continues as 10 - Downtown Seattle'.")
            }
            return String(format: format, trip.routeHeadsign)
        }
    }

    let previous: Row?
    let next: Row?

    /// Empty until the trip's details load. A trip ID the response's references
    /// don't describe gets no row: `TripDetails` resolves both trips from them,
    /// and without one there is no route or headsign to show.
    init(details: TripDetails?) {
        previous = details?.previousTrip.map { Row(order: .previous, trip: $0) }
        next = details?.nextTrip.map { Row(order: .next, trip: $0) }
    }

    func row(_ order: Order) -> Row? {
        switch order {
        case .previous: previous
        case .next: next
        }
    }
}
