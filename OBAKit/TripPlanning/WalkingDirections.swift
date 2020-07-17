//
//  WalkingDirections.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// Provides facilities for calculating walking directions and travel times.
class WalkingDirections: NSObject {

    /// Average human walking speed is 1.4 meters per second (about 3.1 miles per hour).
    private static let walkingVelocity = 1.4

    /// Calculates the travel time in seconds from one location to another, assuming
    /// average human walking speed of 1.4 meters per second (about 3.1 miles per hour).
    /// - Parameter location: Starting location
    /// - Parameter toLocation: Ending location
    public class func travelTime(from location: CLLocation?, to toLocation: CLLocation?) -> TimeInterval? {
        guard let location = location, let toLocation = toLocation else { return nil }
        let distance = location.distance(from: toLocation)
        return distance / walkingVelocity
    }
}
