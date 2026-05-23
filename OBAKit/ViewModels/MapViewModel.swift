//
//  MapViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import CoreLocation
import MapKit
import OBAKitCore

/// Shared ViewModel for the main map screen.
///
/// Consumed by `MapViewController` (UIKit, via Combine `sink`) and by
/// future `NewMapView` (SwiftUI, via `@StateObject`).
/// Contains no UIKit or SwiftUI imports.
///
/// Subclasses NSObject so it can adopt `LocationServiceDelegate`, which is
/// `@objc` (declared in OBAKitCore for legacy Obj-C interop). Other map
/// delegates (`MapRegionDelegate`, `MapPanelDelegate`) intentionally stay
/// on `MapViewController` because their callbacks are UIKit/router-shaped,
/// not state-shaped.
@MainActor
class MapViewModel: NSObject, ObservableObject, LocationServiceDelegate {

    // MARK: - Published State

    /// The current weather forecast, if loaded.
    @Published private(set) var weather: WeatherForecast?

    /// `true` when the map is zoomed out too far to load stops.
    /// Written only through `updateZoomWarning(_:)` so the VC's `MapRegionDelegate`
    /// callback routes through the VM rather than mutating published state directly.
    @Published private(set) var showZoomWarning = false

    /// The currently selected base map type (standard vs. hybrid). Persisted by MapRegionManager.
    @Published private(set) var mapType: MKMapType

    /// The current location authorization status. Used by the UI to show/hide location controls.
    @Published private(set) var locationAuthStatus: CLAuthorizationStatus

    // MARK: - Private

    let application: Application

    // MARK: - Init

    init(application: Application) {
        self.application = application
        self.mapType = application.mapRegionManager.userSelectedMapType
        self.locationAuthStatus = application.locationService.authorizationStatus
        super.init()
        application.locationService.addDelegate(self)
    }

    deinit {
        application.locationService.removeDelegate(self)
    }

    // MARK: - Lifecycle

    /// Call from `viewDidAppear` / `.task`.
    func start() {
        reloadBookmarks()
        Task { [weak self] in await self?.loadWeather() }
    }

    // MARK: - Weather

    func loadWeather() async {
        guard let apiService = application.obacoService else { return }
        do {
            weather = try await apiService.getWeather()
        } catch {
            weather = nil
            Logger.error("Failed to load weather: \(error.localizedDescription)")
        }
    }

    // MARK: - Zoom Warning

    /// Updates the "zoomed out too far" banner state. Called by the VC's
    /// `MapRegionDelegate.mapRegionManagerShowZoomInStatus` callback.
    func updateZoomWarning(_ show: Bool) {
        showZoomWarning = show
    }

    // MARK: - Map Type

    /// Toggles between the standard and hybrid base map types and persists the selection.
    func toggleMapType() {
        let newType: MKMapType = application.mapRegionManager.userSelectedMapType == .mutedStandard ? .hybrid : .mutedStandard
        application.mapRegionManager.userSelectedMapType = newType
        mapType = newType
    }

    // MARK: - Bookmarks

    func reloadBookmarks() {
        guard let region = application.currentRegion else { return }
        application.mapRegionManager.bookmarks = application.userDataStore.findBookmarks(in: region)
    }

    // MARK: - App Lifecycle (EC12)

    /// Call when the app becomes active after a background stint.
    /// Re-fetches weather so the display stays fresh without relying on UIKit notification names.
    func onAppBecameActive() {
        Task { [weak self] in await self?.loadWeather() }
    }

    // MARK: - LocationServiceDelegate

    nonisolated func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.locationAuthStatus = status
        }
    }
}
