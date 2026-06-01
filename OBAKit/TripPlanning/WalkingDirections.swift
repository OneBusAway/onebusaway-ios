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
import OBAKitCore

/// Provides facilities for calculating walking directions and travel times.
class WalkingDirections: NSObject {

    /// Calculates travel time, optionally using a custom walking velocity.
    /// - Parameter location: Starting location
    /// - Parameter toLocation: Ending location
    /// - Parameter velocity: Walking speed in meters per second. Defaults to the average human walking speed.
    public class func travelTime(
        from location: CLLocation?,
        to toLocation: CLLocation?,
        velocity: Double = WalkingSpeed.defaultMetersPerSecond
    ) -> TimeInterval? {
        guard let location = location, let toLocation = toLocation, velocity > 0 else { return nil }
        return location.distance(from: toLocation) / velocity
    }
}
