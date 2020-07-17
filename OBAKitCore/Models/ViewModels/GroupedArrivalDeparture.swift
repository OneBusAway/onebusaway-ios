//
//  GroupedArrivalDeparture.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
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
