//
//  TripPlanEmptyEndpoints.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OTPKit

/// R11 amendment: the endpoints OTPKit reports in `tripPlanEmpty` win over
/// the ones OBAKit passed in, because the rider may have edited them inside
/// the planner form. Each end falls back to the original only when its
/// notification value is missing.
enum TripPlanEmptyEndpoints {
    static func resolve(
        userInfo: [AnyHashable: Any]?,
        fallbackOrigin: CLLocationCoordinate2D?,
        fallbackDestination: CLLocationCoordinate2D?
    ) -> (origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D)? {
        let origin = coordinate(userInfo, Notifications.tripPlanEmptyOriginLatitudeKey, Notifications.tripPlanEmptyOriginLongitudeKey) ?? fallbackOrigin
        let destination = coordinate(userInfo, Notifications.tripPlanEmptyDestinationLatitudeKey, Notifications.tripPlanEmptyDestinationLongitudeKey) ?? fallbackDestination
        guard let origin, let destination else { return nil }
        return (origin, destination)
    }

    private static func coordinate(_ userInfo: [AnyHashable: Any]?, _ latitudeKey: String, _ longitudeKey: String) -> CLLocationCoordinate2D? {
        guard let latitude = userInfo?[latitudeKey] as? Double, let longitude = userInfo?[longitudeKey] as? Double else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
