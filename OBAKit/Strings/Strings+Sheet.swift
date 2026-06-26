//
//  Strings+Sheet.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Localized strings consumed by the SwiftUI sheet surfaces
/// (`MapPanelRootView` and its views).
public extension Strings {

    // MARK: - Route Picker

    static let routePickerTitle = OBALoc(
        "route_picker.title",
        value: "Select Your Route",
        comment: "Title for the route picker screen where the user selects their transit route."
    )

    static let routePickerSearchPlaceholder = OBALoc(
        "route_picker.search_placeholder",
        value: "Search routes…",
        comment: "Placeholder text in the route search field."
    )

    static let routePickerLoading = OBALoc(
        "route_picker.loading",
        value: "Loading routes…",
        comment: "Loading message while fetching nearby routes."
    )

    static let routePickerNoRoutes = OBALoc(
        "route_picker.no_routes",
        value: "No routes found nearby.",
        comment: "Message when no routes are found near the user's location."
    )

    // MARK: - Current Trip

    static let currentTripTitle = OBALoc(
        "current_trip_controller.my_trip",
        value: "My Trip",
        comment: "Title for the current trip screen."
    )

    static let currentTripFindingVehicle = OBALoc(
        "current_trip_controller.detecting",
        value: "Finding your vehicle…",
        comment: "Loading message while searching for the user's vehicle."
    )

    static let currentTripLocationUnavailable = OBALoc(
        "current_trip_controller.location_unavailable",
        value: "Location unavailable. Please enable location services.",
        comment: "Error message when the user's location is not available."
    )

    static let currentTripNoActiveVehicle = OBALoc(
        "current_trip_controller.no_results",
        value: "No active vehicle found on this route near you",
        comment: "Message when no active vehicle is found near the user on the selected route."
    )

    static let currentTripNoRealtime = OBALoc(
        "current_trip_controller.no_realtime",
        value: "No real-time tracking available for this route",
        comment: "Message when the route has no real-time tracking data."
    )

    static let currentTripTryAgain = OBALoc(
        "current_trip_controller.retry",
        value: "Try Again",
        comment: "Button to retry finding the user's vehicle."
    )

    static let currentTripMultipleVehicles = OBALoc(
        "current_trip_controller.multiple_vehicles",
        value: "Multiple vehicles found",
        comment: "Section header when multiple vehicles are found on the selected route."
    )

    static let currentTripDistanceFormat = OBALoc(
        "current_trip_controller.distance_fmt",
        value: "%@ away",
        comment: "Distance from user to vehicle. e.g. '0.2 mi away'"
    )
}
