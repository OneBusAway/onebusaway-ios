//
//  GroupedArrivalDeparture.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/14/19.
//

import Foundation

/// Provides a container for a list of `ArrivalDeparture` objects to be grouped by `Route`.
public struct GroupedArrivalDeparture {
    public let route: Route
    public let arrivalDepartures: [ArrivalDeparture]
}

public extension Sequence where Element == GroupedArrivalDeparture {

    /// Performs a localized case insensitive sort on the receiver.
    ///
    /// - Returns: A localized, case-insensitive sorted Array.
    func localizedStandardCompare() -> [Element] {
        return sorted { (s1, s2) -> Bool in
            return s1.route.shortName.localizedStandardCompare(s2.route.shortName) == .orderedAscending
        }
    }
}
