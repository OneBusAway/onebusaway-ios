//
//  ModelExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/14/19.
//

import Foundation

public extension Sequence where Element == Route {

    /// Performs a localized case insensitive sort on the receiver.
    ///
    /// - Returns: A localized, case-insensitive sorted Array.
    func localizedCaseInsensitiveSort() -> [Element] {
        return sorted { (s1, s2) -> Bool in
            return s1.shortName.localizedCaseInsensitiveCompare(s2.shortName) == .orderedAscending
        }
    }
}

public extension Sequence where Element == ArrivalDeparture {
    /// Filters out all `ArrivalDeparture` objects from the receiver that should be hidden according to `preferences`.
    /// - Parameter preferences: The `StopPreferences` object that will be used to hide `ArrivalDeparture`s.
    func filter(preferences: StopPreferences) -> [ArrivalDeparture] {
        filter { !preferences.isRouteIDHidden($0.routeID) }
    }

    /// Filters out `Route`s that are marked as hidden by `preferences`, and then groups the remaining `ArrivalDeparture`s by `Route`.
    /// - Parameter preferences: The `StopPreferences` object that will be used to hide `ArrivalDeparture`s.
    /// - Parameter filter: Whether the groups should also be filtered (i.e. have `Route`s hidden).
    func group(preferences: StopPreferences, filter: Bool) -> [GroupedArrivalDeparture] {
        let hiddenRoutes = Set(preferences.hiddenRoutes)

        var groups = [Route: [ArrivalDeparture]]()

        for arrDep in self {
            if filter && hiddenRoutes.contains(arrDep.routeID) {
                continue
            }

            var list = groups[arrDep.route, default: [ArrivalDeparture]()]
            list.append(arrDep)
            groups[arrDep.route] = list
        }

        return groups.map { (k, v) -> GroupedArrivalDeparture in
            GroupedArrivalDeparture(route: k, arrivalDepartures: v)
        }
    }
}
