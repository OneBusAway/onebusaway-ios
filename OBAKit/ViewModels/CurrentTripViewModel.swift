//
//  CurrentTripViewModel.swift
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

/// Shared ViewModel for the "find my current trip on a selected route" screen.
///
/// Consumed by `CurrentTripViewController` (UIKit, via Combine `sink`) and by
/// future SwiftUI consumers (via `@StateObject`).
/// Contains no UIKit imports.
@MainActor
class CurrentTripViewModel: ObservableObject {

    /// Loading / error / result state for the screen.
    enum State {
        case loading
        case noLocation
        case noResults
        case noRealtime
        case multipleResults
        case error(Error)
    }

    // MARK: - Published State

    @Published private(set) var state: State = .loading

    /// Matches found near the user. Empty unless `state == .multipleResults` or a
    /// single match has just produced a `pendingNavigation` event.
    @Published private(set) var matchResults: [NearbyTripMatcher.MatchResult] = []

    /// Set when exactly one match is found. UIKit consumers sink this and perform
    /// the navigation push; SwiftUI consumers bind it to `.navigationDestination(item:)`.
    /// Settable so consumers can clear it after acting (and so SwiftUI bindings can
    /// drive it to `nil` on pop).
    @Published var pendingNavigation: ArrivalDeparture?

    // MARK: - Private

    private let application: Application
    private let route: Route
    private var findVehicleTask: Task<Void, Never>?

    // MARK: - Init

    init(application: Application, route: Route) {
        self.application = application
        self.route = route
    }

    deinit {
        findVehicleTask?.cancel()
    }

    // MARK: - Intent

    /// Cancels any in-flight find, then starts a new search.
    func findVehicle() {
        findVehicleTask?.cancel()

        findVehicleTask = Task { [weak self] in
            guard let self else { return }

            guard let userLocation = self.application.locationService.currentLocation else {
                self.state = .noLocation
                return
            }

            guard let apiService = self.application.apiService else {
                self.state = .error(Self.noServiceError())
                return
            }

            let cachedStops = self.application.mapRegionManager.stops

            do {
                let results = try await NearbyTripMatcher.findTrips(
                    for: self.route,
                    near: userLocation,
                    using: apiService,
                    stops: cachedStops
                )
                if Task.isCancelled { return }
                self.handle(results: results)
            } catch is CancellationError {
                return
            } catch {
                self.handle(error: error)
            }
        }
    }

    /// Applies a fresh set of matches. Internal so tests can drive the result branches
    /// directly without staging a full `NearbyTripMatcher` round trip.
    func handle(results: [NearbyTripMatcher.MatchResult]) {
        matchResults = results

        switch results.count {
        case 0:
            state = .noResults
        case 1:
            pendingNavigation = results[0].arrivalDeparture
        default:
            state = .multipleResults
        }
    }

    /// Maps a matcher error onto VM state. Internal so tests can drive both branches.
    func handle(error: Error) {
        if let matchError = error as? NearbyTripMatcher.MatchError, matchError == .noRealtimeData {
            state = .noRealtime
        } else {
            Logger.error("Failed to find trips: \(error)")
            state = .error(error)
        }
    }

    /// Called by a UIKit consumer that cannot perform the single-match navigation
    /// (e.g. the VC isn't embedded in a `UINavigationController`). Falls back to
    /// the disambiguation list so the user can still act on the match. `matchResults`
    /// already holds the single result from `handle(results:)`.
    func pendingNavigationUnavailable() {
        state = .multipleResults
        pendingNavigation = nil
    }

    // MARK: - Helpers

    private static func noServiceError() -> NSError {
        NSError(
            domain: "CurrentTripViewModel",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: OBALoc(
                "current_trip_controller.error_no_service",
                value: "Unable to connect to the transit service.",
                comment: "Error when the API service is unavailable."
            )]
        )
    }
}
