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
        /// Initial state, and while a find is in flight.
        case loading
        /// No user location is available — the location service returned `nil`.
        case noLocation
        /// The matcher returned an empty array — no active vehicle is currently
        /// on the selected route near the user.
        case noResults
        /// The selected route has no real-time tracking data.
        case noRealtime
        /// Two or more vehicles matched; the UI shows a disambiguation list.
        case multipleResults
        /// A network or service error surfaced from the matcher.
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

    // MARK: - Configuration

    /// Set by the UI layer to gate programmatic auto-refreshes.
    /// e.g. `viewModel.shouldSkipProgrammaticRefresh = { UIAccessibility.isVoiceOverRunning }`
    var shouldSkipProgrammaticRefresh: (() -> Bool)?

    // MARK: - Private

    private let application: Application
    private let route: Route
    private static let refreshInterval: TimeInterval = 20.0
    private var refreshTimer: Timer?
    private var findVehicleTask: Task<Void, Never>?

    // MARK: - Init

    init(application: Application, route: Route) {
        self.application = application
        self.route = route
    }

    deinit {
        refreshTimer?.invalidate()
        findVehicleTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Call from `viewWillAppear`. Starts the refresh timer and kicks off an initial find.
    func start() {
        startRefreshTimer()
        findVehicle()
    }

    /// Call from `viewWillDisappear`. Stops the timer and cancels any in-flight find.
    func deactivate() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        findVehicleTask?.cancel()
        findVehicleTask = nil
    }

    // MARK: - Intent

    /// Cancels any in-flight find, then starts a new search.
    func findVehicle() {
        findVehicleTask?.cancel()

        findVehicleTask = Task { [weak self] in
            guard let self else { return }
            // `deactivate()` cancels the task. Bail out before the synchronous early-return
            // paths so a cancelled task can't still publish a final `.noLocation` / `.error`.
            if Task.isCancelled { return }

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

    /// Routes a fresh set of matches into the appropriate state transition:
    /// empty → `.noResults`, one → `pendingNavigation`, more → `.multipleResults`.
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

    /// Maps a matcher error onto VM state. `MatchError.noRealtimeData` gets its own
    /// `.noRealtime` state; everything else surfaces as `.error(error)`.
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

    // MARK: - Refresh Timer

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !(self.shouldSkipProgrammaticRefresh?() ?? false) else { return }
                self.findVehicle()
            }
        }
    }

    // MARK: - Helpers

    /// Builds the localized "transit service unavailable" error used when no
    /// `apiService` is resolved (e.g. the user has no region selected).
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
