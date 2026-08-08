//
//  HomeSheetViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

// MARK: - HomeSheetViewModel

// Owns the home sheet's reactive content state. Empty today beyond a stub
// for the nearby-stops snapshot — kept here so `HomeSheetView`'s
// `@StateObject` + `@autoclosure` plumbing is already in place and the
// next reader sees the intended shape rather than an unexplained empty type.
@MainActor
final class HomeSheetViewModel: ObservableObject {
    // TODO: Populate from `RESTAPIService` / `LocationService` once the
    // home sheet renders nearby stops.
    @Published private(set) var nearbyStops: [Stop] = []

    private let application: Application

    init(application: Application) {
        self.application = application
    }

    /// Mirrors `MapFloatingPanelController.updateSearchBarPlaceholderText()`.
    var searchPlaceholder: String {
        guard let region = application.regionsService.currentRegion else { return "" }
        if application.features.tripPlanning == .running {
            return OBALoc(
                "map_floating_panel.where_are_you_going",
                value: "Where are you going?",
                comment: "Search bar placeholder on the map floating panel when the trip planner is enabled."
            )
        }
        return Formatters.searchPlaceholderText(region: region)
    }
}
