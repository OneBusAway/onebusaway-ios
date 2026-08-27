//
//  VehicleCoordinateUpdate.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import OBAKitCore
import UIKit

/// Whether a vehicle marker should interpolate to a new coordinate or jump.
///
/// Arrival polls land every 15–30s. Assigning `coordinate` each time teleports
/// the pin; interpolating every hop looks like motion. Distances larger than
/// one or two polls at motorway speed are a new fix (or a trip change), not
/// something to ease across the map.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1109
enum VehicleCoordinateUpdate {
    enum Decision: Equatable {
        case unchanged
        case snap
        case animate(duration: TimeInterval)
    }

    static let animationDuration: TimeInterval = 0.8

    /// A bit over one 30s poll at ~50 km/h. Farther than that, jump.
    static let snapBeyondMeters: CLLocationDistance = 500

    /// GPS jitter below this is not worth restarting an in-flight animation.
    static let ignoreBelowMeters: CLLocationDistance = 2

    static func decision(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Decision {
        guard CLLocationCoordinate2DIsValid(from), CLLocationCoordinate2DIsValid(to) else {
            return .snap
        }
        if from.isNullIsland || to.isNullIsland {
            return .snap
        }

        let meters = from.distance(from: to)
        if meters < ignoreBelowMeters { return .unchanged }
        if meters > snapBeyondMeters { return .snap }
        return .animate(duration: animationDuration)
    }

    /// Moves `annotation` according to `decision(from:to:)`.
    ///
    /// The caller is responsible for restoring `from` after any `tripStatus`
    /// assignment: `VehicleAnnotation.tripStatus`'s `didSet` writes
    /// `lastKnownLocation` onto `coordinate` immediately, which would skip
    /// the animation if left in place.
    static func apply(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, on annotation: MKPointAnnotation) {
        switch decision(from: from, to: to) {
        case .unchanged:
            break
        case .snap:
            annotation.coordinate = to
        case .animate(let duration):
            UIView.animate(withDuration: duration, delay: 0, options: [.curveLinear, .beginFromCurrentState]) {
                annotation.coordinate = to
            }
        }
    }
}
