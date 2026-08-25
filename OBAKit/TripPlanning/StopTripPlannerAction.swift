//
//  StopTripPlannerAction.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore

/// Stop-page trip-planner menu actions. Menus and toolbars can gate on
/// `isAvailable` without instantiating a view controller.
enum StopTripPlannerAction {
    /// Prefill destination as the stop; origin stays current location.
    case directionsToStop
    /// Prefill origin as the stop; destination left empty for the rider to pick.
    case directionsFromStop

    /// `true` when OTP trip planning is running for the current region and the
    /// rider has not disabled it for that region.
    static func isAvailable(application: Application) -> Bool {
        guard application.features.tripPlanning == .running,
              let region = application.regionsService.currentRegion
                ?? application.currentRegion,
              application.userDataStore.isTripPlanningEnabled(for: region) else {
            return false
        }
        return true
    }

    static var directionsToHereTitle: String {
        OBALoc(
            "stops_controller.directions_to_here",
            value: "Directions to Here",
            comment: "Stop Location menu action that opens the trip planner with this stop as the destination."
        )
    }

    static var directionsFromHereTitle: String {
        OBALoc(
            "stops_controller.directions_from_here",
            value: "Directions from Here",
            comment: "Stop Location menu action that opens the trip planner with this stop as the origin."
        )
    }
}
