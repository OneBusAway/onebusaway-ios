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
import OBAKitCore

/// The selected base map style. UIKit maps `.standard` → `MKMapType.mutedStandard`
/// and `.hybrid` → `MKMapType.hybrid`; SwiftUI can map directly to `MapStyle`.
/// Keeping this MapKit-free matches the `PanelDetent` pattern in `MapPanelViewModel`.
enum MapBaseType {
    case standard
    case hybrid
}

/// Shared ViewModel for the main map screen.
///
/// Consumed by `MapViewController` (UIKit, via Combine `sink`) and by
/// future `NewMapView` (SwiftUI, via `@StateObject`).
/// Contains no UIKit, MapKit, or SwiftUI imports.
///
/// Subclasses NSObject so it can adopt `LocationServiceDelegate`, which is
/// `@objc` (declared in OBAKitCore for legacy Obj-C interop). Other map
/// delegates (`MapRegionDelegate`, `MapPanelDelegate`) intentionally stay
/// on `MapViewController` because their callbacks are UIKit/router-shaped,
/// not state-shaped.
@MainActor
class MapViewModel: NSObject, ObservableObject, LocationServiceDelegate {

    // MARK: - Published State

    /// View-ready weather data, rebuilt only when `loadWeather()` finishes —
    /// SwiftUI body re-reads don't pay the formatting cost. The raw
    /// `WeatherForecast` model isn't surfaced; reintroduce it on demand if a
    /// future consumer needs it.
    @Published private(set) var weatherDisplay: WeatherDisplay?

    /// `true` when the map is zoomed out too far to load stops.
    /// Written only through `updateZoomWarning(_:)` so the VC's `MapRegionDelegate`
    /// callback routes through the VM rather than mutating published state directly.
    @Published private(set) var showZoomWarning = false

    /// The currently selected base map type (standard vs. hybrid).
    /// Persistence is handled by the consuming layer (UIKit: `MapViewController`'s `$mapType` sink).
    @Published private(set) var mapType: MapBaseType

    /// The current location authorization status. Used by the UI to show/hide location controls.
    @Published private(set) var locationAuthStatus: CLAuthorizationStatus

    // MARK: - Private

    private let application: Application

    // MARK: - Init

    init(application: Application, initialMapType: MapBaseType = .standard) {
        self.application = application
        self.mapType = initialMapType
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

    /// `true` when the host should render any weather UI. Mirrors the gate at
    /// `MapViewController.toolbar` so UIKit and SwiftUI agree on availability.
    var isWeatherFeatureAvailable: Bool {
        application.features.obaco == .running
    }

    func loadWeather() async {
        guard let apiService = application.obacoService else { return }
        do {
            let forecast = try await apiService.getWeather()
            weatherDisplay = WeatherDisplay(forecast: forecast, locale: application.locale)
        } catch {
            weatherDisplay = nil
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

    /// Toggles between the standard and hybrid base map types.
    /// The consuming layer (UIKit: `MapViewController`'s `$mapType` sink) persists the selection.
    func toggleMapType() {
        mapType = mapType == .standard ? .hybrid : .standard
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
