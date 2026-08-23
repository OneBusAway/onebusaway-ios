//
//  TripRouteOverlays.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import UIKit

/// Builds the two polylines `TripViewController` draws on its map: gray behind
/// the vehicle, route-colored ahead of it. The SwiftUI trip page already does
/// this via `TripFocusMapLayer`; this is the same split for the UIKit map
/// `TripViewController` still owns.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/444
enum TripRouteOverlays {

    /// - Parameter fraction: `nil` when the trip reports no progress (schedule-
    ///   only, or a feed that omits total distance). The whole shape is then
    ///   ahead — the same choice `TripPageViewController` makes — rather than
    ///   inventing a split point.
    static func make(coordinates: [CLLocationCoordinate2D], fraction: Double?) -> [TripShapeOverlay] {
        let split = fraction.map {
            TripShapeSplit.split(coordinates: coordinates, atFraction: $0)
        } ?? TripShapeSplit.Result(spent: [], ahead: coordinates)

        var overlays: [TripShapeOverlay] = []
        if split.spent.count >= 2 {
            overlays.append(TripShapeOverlay.make(coordinates: split.spent, isSpent: true, isCasing: false))
        }
        if split.ahead.count >= 2 {
            overlays.append(TripShapeOverlay.make(coordinates: split.ahead, isSpent: false, isCasing: false))
        }
        return overlays
    }
}

/// Stroke for one half of the UIKit trip polyline. Extracted so a test can
/// assert spent is gray and thinner without loading `TripViewController.view`.
struct TripRouteOverlayAppearance {
    let strokeColor: UIColor
    let lineWidth: CGFloat

    static func make(isSpent: Bool, routeColor: UIColor, needsIncreasedVisibility: Bool) -> TripRouteOverlayAppearance {
        if isSpent {
            return TripRouteOverlayAppearance(strokeColor: .systemGray3, lineWidth: 4)
        }

        var color = routeColor
        if !needsIncreasedVisibility {
            color = color.withAlphaComponent(0.75)
        }
        return TripRouteOverlayAppearance(strokeColor: color, lineWidth: 6)
    }
}
