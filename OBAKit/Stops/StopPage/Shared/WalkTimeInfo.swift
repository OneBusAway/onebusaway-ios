//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// A travel-time estimate at a given speed (§4.5) — walking or cycling, whichever
/// `compute(...)` was called with. `StopViewModel` computes three independent
/// instances from this one type: `headerWalkTime` and `headerBikeTime` (always
/// their own fixed speed, for the header's two chips) and the mode-aware `walkTime`
/// (walking or cycling speed depending on Bike Mode, for the chronological
/// partition and divider) — so unlike this type's single-source origin, the header
/// chips and the divider do NOT necessarily share one instance anymore; they only
/// have to agree when Bike Mode is off, or the header and the divider would show
/// different rounded minutes for what should read as the same walk-speed estimate.
struct WalkTimeInfo: Equatable {
    /// Rounded up — never promise a shorter walk (or bike ride) than reality.
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
