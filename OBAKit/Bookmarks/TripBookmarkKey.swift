//
//  TripBookmarkKey.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/15/20.
//

import Foundation
import OBAKitCore

/// Provides a way to group `ArrivalDeparture`s by the data elements used in trip bookmarks.
struct TripBookmarkKey: Hashable, Equatable {
    let stopID: String
    let routeShortName: String
    let routeID: RouteID
    let tripHeadsign: String

    init?(bookmark: Bookmark) {
        guard
            let routeShortName = bookmark.routeShortName,
            let routeID = bookmark.routeID,
            let tripHeadsign = bookmark.tripHeadsign
        else {
            return nil
        }
        self.stopID = bookmark.stopID
        self.routeShortName = routeShortName
        self.routeID = routeID
        self.tripHeadsign = tripHeadsign
    }

    init(arrivalDeparture: ArrivalDeparture) {
        self.stopID = arrivalDeparture.stopID
        self.routeShortName = arrivalDeparture.routeShortName
        self.routeID = arrivalDeparture.routeID
        self.tripHeadsign = arrivalDeparture.tripHeadsign ?? ""
    }

    /// A composite of the route name and headsign.
    public var routeAndHeadsign: String {
        return "\(routeShortName) - \(tripHeadsign)"
    }
}

extension Sequence where Element == ArrivalDeparture {
    /// Creates a mapping of `TripBookmarkKey`s to `ArrivalDeparture`s so that
    /// it is easier to load data and inject `ArrivalDeparture` objects into `StopArrivalView`s.
    /// - Note: Also sorts the list of `ArrivalDeparture`s.
    var tripKeyGroupedElements: [TripBookmarkKey: [ArrivalDeparture]] {
        var keysAndDeps = [TripBookmarkKey: [ArrivalDeparture]]()

        for arrDep in self {
            let key = TripBookmarkKey(arrivalDeparture: arrDep)

            var departures = keysAndDeps[key, default: [ArrivalDeparture]()]
            departures.append(arrDep)
            keysAndDeps[key] = departures.sorted { $0.arrivalDepartureDate < $1.arrivalDepartureDate }
        }

        return keysAndDeps
    }

    /// Returns the unique set of `TripBookmarkKey`s contained by this list of `ArrivalDeparture`s.
    var uniqueTripKeys: [TripBookmarkKey] {
        Set(self.map { TripBookmarkKey(arrivalDeparture: $0) }).allObjects
    }
}
