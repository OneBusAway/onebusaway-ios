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
/// `canPresent` without instantiating a view controller.
enum StopTripPlannerAction {
    /// Prefill destination as the stop; origin stays current location.
    case directionsToStop
    /// Prefill origin as the stop; destination left empty for the rider to pick.
    case directionsFromStop

    /// `true` when OTP trip planning is running for the current region and the
    /// rider has not disabled it for that region. Does not imply the classic
    /// map tab can present the planner — see `canPresent`.
    static func isAvailable(application: Application) -> Bool {
        guard application.features.tripPlanning == .running,
              let region = application.regionsService.currentRegion
                ?? application.currentRegion,
              application.userDataStore.isTripPlanningEnabled(for: region) else {
            return false
        }
        return true
    }

    /// Hide the stop-page actions unless the classic tab root can host
    /// `MapViewController.showTripPlanner`. Map-panel mode leaves
    /// `viewRouter.rootController` nil; showing the rows there would be a
    /// dead button.
    static func canPresent(application: Application) -> Bool {
        isAvailable(application: application) && application.viewRouter.rootController != nil
    }

    /// Pops to the map tab and opens the existing trip planner. No-ops (with
    /// a log) when `canPresent` is false.
    static func present(_ action: StopTripPlannerAction, stop: Stop, application: Application) {
        guard canPresent(application: application),
              let rootController = application.viewRouter.rootController else {
            if isAvailable(application: application) {
                Logger.error("StopTripPlannerAction: present dropped — no classic root controller (map-panel mode is active)")
            }
            return
        }

        application.viewRouter.rootNavigateTo(page: .map)

        let mapController = rootController.mapController
        mapController.navigationController?.popToRootViewController(animated: false)

        let stopMapItem = TripPlannerEndpoints.mapItem(from: stop)
        switch action {
        case .directionsToStop:
            mapController.showTripPlanner(destination: stopMapItem)
        case .directionsFromStop:
            mapController.showTripPlanner(origin: stopMapItem, destination: nil)
        }
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
