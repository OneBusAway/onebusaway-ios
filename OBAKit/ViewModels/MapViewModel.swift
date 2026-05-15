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

/// Shared ViewModel for the main map screen.
///
/// Consumed by `MapViewController` (UIKit, via Combine `sink`) and by
/// future `NewMapView` (SwiftUI, via `@StateObject`).
/// Contains no UIKit or SwiftUI imports.
///
/// MapViewModel must subclass NSObject to adopt the @objc MapRegionDelegate
/// and LocationServiceDelegate protocols (EdgeCase 6 in the implementation plan).
@MainActor
class MapViewModel: NSObject, ObservableObject {

    // MARK: - Published State

    /// The current weather forecast, if loaded.
    @Published private(set) var weather: WeatherForecast?

    /// `true` while weather is being fetched.
    @Published private(set) var isLoadingWeather = false

    /// `true` when the map is zoomed out too far to load stops.
    @Published var showZoomWarning = false

    // MARK: - Private

    let application: Application

    // MARK: - Init

    init(application: Application) {
        self.application = application
        super.init()
    }

    // MARK: - Lifecycle

    /// Call from `viewDidAppear` / `.task`.
    func start() {
        reloadBookmarks()
        Task { await loadWeather() }
    }

    /// Call from `viewWillDisappear` / `.onDisappear`.
    func deactivate() { }

    // MARK: - Weather

    func loadWeather() async {
        guard let apiService = application.obacoService else { return }
        isLoadingWeather = true
        do {
            weather = try await apiService.getWeather()
        } catch {
            weather = nil
        }
        isLoadingWeather = false
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
        Task { await loadWeather() }
    }

}
