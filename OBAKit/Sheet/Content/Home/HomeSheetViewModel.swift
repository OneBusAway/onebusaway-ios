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
final class HomeSheetViewModel: NSObject, ObservableObject, RegionsServiceDelegate {
    // TODO: Populate from `RESTAPIService` / `LocationService` once the
    // home sheet renders nearby stops.
    @Published private(set) var nearbyStops: [Stop] = []

    /// Published rather than computed so a region change repaints the search bar.
    /// The UIKit panel gets this from its own `RegionsServiceDelegate` callback
    /// (`MapFloatingPanelController.regionsService(_:updatedRegion:)`); a plain
    /// computed property would leave the placeholder naming the old region until
    /// something unrelated happened to invalidate the view.
    @Published private(set) var searchPlaceholder: String

    private let application: Application

    init(application: Application) {
        self.application = application
        self.searchPlaceholder = SearchPlaceholder.text(for: application)
        super.init()

        // `RegionsService` holds delegates weakly, so there's nothing to unregister.
        application.regionsService.addDelegate(self)
    }

    // MARK: - RegionsServiceDelegate

    func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        searchPlaceholder = SearchPlaceholder.text(for: application)
    }
}
