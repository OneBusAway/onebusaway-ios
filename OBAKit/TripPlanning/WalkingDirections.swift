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

    /// Calculates travel time, optionally using a custom walking velocity.
    /// - Parameter location: Starting location
    /// - Parameter toLocation: Ending location
    /// - Parameter velocity: Walking speed in meters per second. Defaults to 1.4 (average human walking speed).
    public class func travelTime(
        from location: CLLocation?,
        to toLocation: CLLocation?,
        velocity: Double = 1.4
    ) -> TimeInterval? {
        guard let location = location, let toLocation = toLocation else { return nil }
        return location.distance(from: toLocation) / velocity
    }
}
