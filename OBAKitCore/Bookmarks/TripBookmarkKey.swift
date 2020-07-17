//
//  TripBookmarkKey.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Provides a way to group `ArrivalDeparture`s by the data elements used in trip bookmarks.
public struct TripBookmarkKey: Hashable, Equatable {
    let stopID: StopID
    let routeShortName: String
    let routeID: RouteID
    let tripHeadsign: String

    public init?(bookmark: Bookmark) {
        guard
            let routeShortName = bookmark.routeShortName,
            let routeID = bookmark.routeID,
            let tripHeadsign = bookmark.tripHeadsign
        else {
            return nil
        }
        self.init(stopID: bookmark.stopID, routeShortName: routeShortName, routeID: routeID, tripHeadsign: tripHeadsign)
    }

    public init(arrivalDeparture: ArrivalDeparture) {
        self.init(stopID: arrivalDeparture.stopID, routeShortName: arrivalDeparture.routeShortName, routeID: arrivalDeparture.routeID, tripHeadsign: arrivalDeparture.tripHeadsign ?? "")
    }

    public init(stopID: StopID, routeShortName: String, routeID: RouteID, tripHeadsign: String) {
        self.stopID = stopID
        self.routeShortName = routeShortName
        self.routeID = routeID
        self.tripHeadsign = tripHeadsign
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
    public var tripKeyGroupedElements: [TripBookmarkKey: [ArrivalDeparture]] {
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
    public var uniqueTripKeys: [TripBookmarkKey] {
        Set(self.map { TripBookmarkKey(arrivalDeparture: $0) }).allObjects
    }
}
