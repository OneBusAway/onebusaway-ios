//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// The single source of walk time on the Stop page (§4.5): the header chip
/// and the chronological walk line must both read from the same instance.
struct WalkTimeInfo: Equatable {
    /// Rounded up — never promise a shorter walk than reality.
    let walkMinutes: Int
    let distance: CLLocationDistance

    /// Straight-line walk estimate, matching `WalkingDirections.travelTime`.
    /// Returns nil with no user location, an invalid speed, or when the user
    /// is effectively at the stop (<= 40 m, matching `WalkTimeView`).
    static func compute(from userLocation: CLLocation?, to stopLocation: CLLocation?, speedMetersPerSecond: Double) -> WalkTimeInfo? {
        guard let userLocation, let stopLocation else { return nil }
        let distance = userLocation.distance(from: stopLocation)
        // Suppress when effectively at the stop; the speed/velocity guard and the
        // distance-over-velocity math both live in `WalkingDirections.travelTime`.
        guard distance > 40,
              let seconds = WalkingDirections.travelTime(from: userLocation, to: stopLocation, velocity: speedMetersPerSecond)
        else { return nil }
        return WalkTimeInfo(walkMinutes: Int(ceil(seconds / 60.0)), distance: distance)
    }
}
