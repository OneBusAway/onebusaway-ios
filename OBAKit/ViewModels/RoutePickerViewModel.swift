//
//  RoutePickerViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import CoreLocation
import Foundation
import OBAKitCore

/// Shared ViewModel for `RoutePickerViewController`.
///
/// Owns route loading (cache-first, API fallback), search filtering, and load-error
/// surfacing. The VC keeps `UISearchController` and `OBAListView` presentation.
@MainActor
final class RoutePickerViewModel: ObservableObject {

    /// Reasons `loadRoutes()` can fail short of a thrown network/decoding error.
    /// Conforms to `LocalizedError` so a SwiftUI consumer can read
    /// `errorDescription` without going through the typed enum.
    enum RoutePickerError: LocalizedError {
        case serviceUnavailable
        case locationUnavailable

        var errorDescription: String? {
            switch self {
            case .serviceUnavailable:
                return OBALoc(
                    "route_picker.error_no_service",
                    value: "Unable to connect to the transit service.",
                    comment: "Error when the API service is unavailable in the route picker."
                )
            case .locationUnavailable:
                return OBALoc(
                    "route_picker.error_no_location",
                    value: "Location unavailable. Please enable location services to find nearby routes.",
                    comment: "Error when location is unavailable in the route picker."
                )
            }
        }
    }

    // MARK: - Published State

    /// Routes matching the current search filter. Drives the list.
    @Published private(set) var filteredRoutes: [Route] = []

    /// `true` once `loadRoutes()` has resolved (success or failure).
    @Published private(set) var didFinishLoading: Bool = false

    /// Error from the last `loadRoutes()` attempt, or `nil`. Kept as `Error` so a
    /// SwiftUI consumer can classify on type rather than parsing a flattened
    /// `String`. The VC reads `localizedDescription` for display.
    @Published private(set) var loadError: Error?

    // MARK: - Direct Reads (not observed)

    /// All routes available for selection, sorted alphabetically. VC reads to detect
    /// the "no routes found" empty state.
    private(set) var allRoutes: [Route] = []

    // MARK: - Private

    private let application: Application
    private var searchQuery: String = ""

    // MARK: - Init

    init(application: Application) {
        self.application = application
    }

    // MARK: - Load

    func loadRoutes() async {

        didFinishLoading = false
        loadError = nil

        // Primary: extract routes from stops already loaded by MapRegionManager.
        let cachedStops = application.mapRegionManager.stops
        if !cachedStops.isEmpty {
            applyRoutes(from: cachedStops)
            return
        }

        // Fallback: fetch nearby stops from the API.
        guard let apiService = application.apiService else {
            loadError = RoutePickerError.serviceUnavailable
            didFinishLoading = true
            return
        }

        guard let location = application.locationService.currentLocation else {
            loadError = RoutePickerError.locationUnavailable
            didFinishLoading = true
            return
        }

        do {
            let stops = try await apiService.getStops(coordinate: location.coordinate).list
            applyRoutes(from: stops)
        } catch {
            // Cancellation finalizes the load without surfacing an error so a
            // re-observed VM doesn't get stuck on "Loading routes…". Match the
            // three shapes a cancelled request can arrive as:
            //   1. The parent Task itself was cancelled (most common path).
            //   2. Swift Concurrency surfaced `CancellationError`.
            //   3. URLSession returned `URLError(.cancelled)` — which the API
            //      layer re-throws as an `NSError` in the `NSURLErrorDomain`,
            //      so check `NSError.code` against `NSURLErrorCancelled` for
            //      the safest cast.
            let nsError = error as NSError
            let isCancelled = Task.isCancelled
                || error is CancellationError
                || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)

            if isCancelled {
                return
            }
            Logger.error("Failed to load routes for picker: \(error)")
            loadError = error
            didFinishLoading = true
        }
    }

    // MARK: - Search

    func updateSearch(_ query: String) {
        searchQuery = query
        recomputeFilteredRoutes()
    }

    // MARK: - Private

    /// Extracts unique routes from stops, sorts, and refreshes the filtered list.
    private func applyRoutes(from stops: [Stop]) {
        var seen = Set<RouteID>()
        var uniqueRoutes = [Route]()

        for stop in stops {
            for route in stop.routes where seen.insert(route.id).inserted {
                uniqueRoutes.append(route)
            }
        }

        allRoutes = uniqueRoutes.localizedCaseInsensitiveSort()
        didFinishLoading = true
        recomputeFilteredRoutes()
    }

    private func recomputeFilteredRoutes() {
        if searchQuery.isEmpty {
            filteredRoutes = allRoutes
            return
        }
        let query = searchQuery.lowercased()
        filteredRoutes = allRoutes.filter { route in
            route.shortName.lowercased().contains(query)
                || (route.longName?.lowercased().contains(query) ?? false)
        }
    }
}
